import Foundation
import Testing
@testable import ASCKitProject

struct DirectoryListingTests {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "listing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func filesSkipDirectoriesStraysAndHiddenFilesInNaturalOrder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["10.png", "2.png", "Thumbs.db", ".DS_Store", "skip.png"] {
            try Data().write(to: folder.appending(path: name))
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: false)

        let names = DirectoryListing.files(in: folder, ignoring: ["skip.png"]).map(\.lastPathComponent)

        #expect(names == ["2.png", "10.png"])
    }

    @Test func directoriesAreSortedAndMissingFolderIsEmpty() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["b", "a"] {
            try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: false)
        }
        try Data().write(to: folder.appending(path: "file.txt"))

        #expect(DirectoryListing.directories(in: folder).map(\.lastPathComponent) == ["a", "b"])
        #expect(DirectoryListing.entries(in: folder.appending(path: "missing")).isEmpty)
    }
}
