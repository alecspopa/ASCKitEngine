import Foundation

/// Uploads images and videos into an app's library.
///
/// The library has no batch call, so this is as close to one as App Store
/// Connect allows. Files go up in parallel with a limit. After the uploads,
/// one list call per kind of media checks on every asset at once, instead of
/// one call per asset.
public struct LibraryUploader: Sendable {
    private let client: ASCClient

    public init(client: ASCClient) {
        self.client = client
    }

    /// One file to send.
    public struct Item: Sendable, Hashable {
        public let fileURL: URL
        public let media: LibraryMedia
        public let category: LibraryAssetCategory
        public let referenceName: String?
        public let previewFrameTimeCode: String?

        public init(
            fileURL: URL,
            media: LibraryMedia,
            category: LibraryAssetCategory,
            referenceName: String? = nil,
            previewFrameTimeCode: String? = nil
        ) {
            self.fileURL = fileURL
            self.media = media
            self.category = category
            self.referenceName = referenceName
            self.previewFrameTimeCode = previewFrameTimeCode
        }

        public var fileName: String { fileURL.lastPathComponent }
    }

    /// A file whose bytes are in and committed. App Store Connect may still be
    /// processing it.
    public struct Committed: Sendable, Hashable {
        public let item: Item
        public let assetID: String
    }

    public struct Progress: Sendable {
        public let fileName: String
        public let step: Step

        public enum Step: String, Sendable {
            case reserving
            case uploading
            case committing
            case waiting
            case done
        }
    }

    /// How long to keep asking Apple whether it has finished with an image.
    public struct PollSettings: Sendable {
        public var interval: Duration
        public var attempts: Int

        public init(interval: Duration = .seconds(2), attempts: Int = 30) {
            self.interval = interval
            self.attempts = attempts
        }

        /// For tests, where nothing should sleep.
        public static let immediate = PollSettings(interval: .zero, attempts: 3)
    }

    /// How many files go up at the same time. Each file sends its own parts in
    /// parallel too, so this stays small.
    public static let defaultLimit = 4

    /// Uploads every item, at most `limit` at once.
    ///
    /// A file that fails does not stop the others. Each one that commits is
    /// handed to `onCommit` straight away, so the caller can write it down
    /// before anything else can fail.
    public func upload(
        _ items: [Item],
        libraryID: String,
        limit: Int = defaultLimit,
        progress: (@Sendable (Progress) -> Void)? = nil,
        onCommit: (@Sendable (Committed) async -> Void)? = nil
    ) async -> [Item: Result<Committed, any Error>] {
        await withTaskGroup(of: (Item, Result<Committed, any Error>).self) { group in
            var results: [Item: Result<Committed, any Error>] = [:]
            var pending = items[...]
            var running = 0

            func startNext() {
                guard let item = pending.popFirst() else { return }
                running += 1
                group.addTask {
                    do {
                        let committed = try await upload(item, libraryID: libraryID, progress: progress)
                        await onCommit?(committed)
                        return (item, .success(committed))
                    } catch {
                        return (item, .failure(error))
                    }
                }
            }

            for _ in 0 ..< max(1, limit) {
                startNext()
            }
            while running > 0, let (item, result) = await group.next() {
                running -= 1
                results[item] = result
                startNext()
            }
            return results
        }
    }

    /// Reserve, send the parts, commit. The wait comes later, for all of them
    /// together.
    public func upload(
        _ item: Item,
        libraryID: String,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Committed {
        let fileName = item.fileName
        let data = try Data(contentsOf: item.fileURL, options: .mappedIfSafe)

        progress?(Progress(fileName: fileName, step: .reserving))
        let reserved = try await client.reserveLibraryAsset(
            media: item.media,
            libraryID: libraryID,
            category: item.category,
            fileName: fileName,
            fileSize: data.count,
            referenceName: item.referenceName,
            previewFrameTimeCode: item.previewFrameTimeCode
        )

        guard let operations = reserved.attributes?.uploadOperations, operations.isEmpty == false else {
            throw UploadError.noUploadInstructions(fileName: fileName)
        }

        progress?(Progress(fileName: fileName, step: .uploading))
        try await client.sendParts(operations, of: data, fileName: fileName, attemptsPerPart: 2)

        progress?(Progress(fileName: fileName, step: .committing))
        _ = try await client.commitLibraryAsset(media: item.media, id: reserved.id)

        progress?(Progress(fileName: fileName, step: .done))
        return Committed(item: item, assetID: reserved.id)
    }

    /// Waits until App Store Connect has processed every asset, asking about
    /// all of them in one call per round.
    ///
    /// The answer holds the state of each asset: one a placement can use, or
    /// `failed` with Apple's reason. An asset still processing after the last
    /// round is in the answer with its processing state.
    public func waitUntilProcessed(
        _ ids: [LibraryMedia: [String]],
        libraryID: String,
        poll: PollSettings = PollSettings()
    ) async throws -> [String: Resource<LibraryAssetAttributes>] {
        var known: [String: Resource<LibraryAssetAttributes>] = [:]
        var waiting = ids.filter { $0.value.isEmpty == false }

        for attempt in 1 ... max(1, poll.attempts) {
            guard waiting.isEmpty == false else { break }
            if attempt > 1, poll.interval > .zero {
                try await Task.sleep(for: poll.interval)
            }

            for (media, assetIDs) in waiting {
                let read = try await client.libraryAssets(libraryID: libraryID, media: media, ids: assetIDs)
                for asset in read {
                    known[asset.id] = asset
                }
                let stillProcessing = assetIDs.filter { id in
                    known[id]?.attributes?.state?.isProcessing ?? true
                }
                waiting[media] = stillProcessing.isEmpty ? nil : stillProcessing
            }
        }
        return known
    }
}

public extension LibraryUploader.Committed {
    /// Apple's reason for a failed asset, as the error a push reports.
    static func failure(
        fileName: String,
        asset: Resource<LibraryAssetAttributes>
    ) -> UploadError {
        UploadError.appleRejectedTheImage(
            fileName: fileName,
            details: asset.attributes?.stateDetails?.map(\.asErrorDetail) ?? []
        )
    }
}

// MARK: - Parts

extension ASCClient {
    /// Sends every part where App Store Connect said to. Apple says the parts
    /// may go at the same time and in any order.
    ///
    /// A part that fails for a reason a second try can get past goes once
    /// more. The address stays good for a while, and starting the whole file
    /// again would reserve a second asset.
    func sendParts(
        _ operations: [UploadOperation],
        of data: Data,
        fileName: String,
        attemptsPerPart: Int = 1
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for operation in operations {
                guard let url = URL(string: operation.url) else {
                    throw UploadError.badUploadURL(fileName: fileName, url: operation.url)
                }

                let end = operation.offset + operation.length
                guard operation.offset >= 0, end <= data.count else {
                    throw UploadError.partOutsideTheFile(fileName: fileName)
                }
                let part = data.subdata(in: operation.offset ..< end)

                group.addTask {
                    try await sendPart(operation, to: url, body: part, attempts: attemptsPerPart)
                }
            }
            try await group.waitForAll()
        }
    }

    private func sendPart(
        _ operation: UploadOperation,
        to url: URL,
        body: Data,
        attempts: Int
    ) async throws {
        for attempt in 1 ... max(1, attempts) {
            do {
                try await uploadPart(to: url, method: operation.method, headers: operation.requestHeaders, body: body)
                return
            } catch let error as ASCError where error.isWorthRetrying && attempt < attempts {
                try Task.checkCancellation()
            }
        }
    }
}

// MARK: - Errors

public enum UploadError: Error, CustomLocalizedStringResourceConvertible {
    case noUploadInstructions(fileName: String)
    case badUploadURL(fileName: String, url: String)
    case partOutsideTheFile(fileName: String)
    case appleRejectedTheImage(fileName: String, details: [ASCErrorDetail])
    case stillProcessing(fileName: String, afterAttempts: Int)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noUploadInstructions(fileName):
            LocalizedStringResource("""
            App Store Connect reserved \(fileName) but said nothing about where to send it.
            """, bundle: .here)
        case let .badUploadURL(fileName, url):
            LocalizedStringResource("""
            App Store Connect gave an address for \(fileName) that is not a URL: \(url)
            """, bundle: .here)
        case let .partOutsideTheFile(fileName):
            LocalizedStringResource("""
            App Store Connect asked for a part of \(fileName) that is past the end of it.
            """, bundle: .here)
        case let .appleRejectedTheImage(fileName, details):
            reasonsRefused(fileName: fileName, details: details)
        case let .stillProcessing(fileName, attempts):
            LocalizedStringResource("""
            App Store Connect is still working on \(fileName) after \(attempts) checks. \
            It may yet finish. Read it back with asckit diff before uploading it again.
            """, bundle: .here)
        }
    }

    private func reasonsRefused(fileName: String, details: [ASCErrorDetail]) -> LocalizedStringResource {
        guard let said = details.sentences else {
            return LocalizedStringResource("App Store Connect refused \(fileName) and did not say why.", bundle: .here)
        }
        return LocalizedStringResource("App Store Connect refused \(fileName). App Store Connect said: \(said)", bundle: .here)
    }
}

extension UploadError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
