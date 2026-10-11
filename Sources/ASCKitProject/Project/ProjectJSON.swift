import Foundation

/// The one way the project files are written, so a file reads the same
/// whichever code made it.
enum ProjectJSON {
    static func encoder(pretty: Bool = true, datesAsISO8601: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
        if datesAsISO8601 { encoder.dateEncodingStrategy = .iso8601 }
        return encoder
    }

    static func decoder(datesAsISO8601: Bool = false) -> JSONDecoder {
        let decoder = JSONDecoder()
        if datesAsISO8601 { decoder.dateDecodingStrategy = .iso8601 }
        return decoder
    }

    /// Makes the folder the file goes in first, so no caller has to.
    static func write(
        _ value: some Encodable,
        to url: URL,
        pretty: Bool = true,
        datesAsISO8601: Bool = false,
        atomic: Bool = false
    ) throws {
        let data = try encoder(pretty: pretty, datesAsISO8601: datesAsISO8601).encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: atomic ? .atomic : [])
    }

    /// Nil when the file is not there or does not decode. Use it only where
    /// both mean the same thing, such as a cache.
    static func read<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        datesAsISO8601: Bool = false
    ) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder(datesAsISO8601: datesAsISO8601).decode(type, from: data)
    }
}
