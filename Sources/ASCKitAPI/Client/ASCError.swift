import Foundation

/// One entry from Apple's error envelope.
public struct ASCErrorDetail: Sendable, Hashable, Decodable {
    public let id: String?
    public let status: String?
    public let code: String?
    public let title: String?
    public let detail: String?
    public let pointer: String?

    private enum CodingKeys: String, CodingKey {
        case id, status, code, title, detail, source
    }

    private struct Source: Decodable {
        let pointer: String?
        let parameter: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        pointer = try container.decodeIfPresent(Source.self, forKey: .source)?.pointer
    }

    public init(id: String? = nil, status: String? = nil, code: String? = nil,
                title: String? = nil, detail: String? = nil, pointer: String? = nil) {
        self.id = id
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.pointer = pointer
    }
}

struct ASCErrorEnvelope: Decodable {
    let errors: [ASCErrorDetail]
}

public enum ASCError: Error {
    case notAnHTTPResponse

    /// 401. The token was refused. Usually a clock problem or the wrong key id.
    case unauthorized(details: [ASCErrorDetail])

    /// 401 for a token that named no issuer, which is how an individual key
    /// signs. A project with no `issuerId` signs every token that way, so a
    /// team key in such a project is refused on every request. Apple says only
    /// NOT_AUTHORIZED, which names the effect rather than the cause.
    case unauthorizedIndividualKey(details: [ASCErrorDetail])

    /// 403. Almost always the key's role. Writing metadata needs App Manager or
    /// higher, and a Developer key reads fine right up until the first write.
    case forbidden(details: [ASCErrorDetail])

    case notFound(details: [ASCErrorDetail])

    /// 409. The resource is in a state that refuses this change, or a
    /// relationship id is stale. `pointer` names the field Apple objected to.
    case conflict(details: [ASCErrorDetail])

    /// 422. A value Apple would not accept, such as a field over its limit.
    case unprocessable(details: [ASCErrorDetail])

    case rateLimited(rateLimit: RateLimit?, details: [ASCErrorDetail])

    /// Apple returns 500 in places where a 4xx belongs, so this is not always a
    /// fault on their side. The commit step of an image upload is the known one.
    case serverError(status: Int, details: [ASCErrorDetail])

    case unexpectedStatus(status: Int, details: [ASCErrorDetail], body: Data)

    case decodingFailed(underlying: any Error, body: Data)

    /// The request never reached App Store Connect, or the answer never came
    /// back. A timeout, a dropped connection, or no network at all.
    case transportFailed(underlying: URLError)

    /// A URLSession failure as something this app can explain.
    ///
    /// A cancelled request is not a fault. It is this app stopping its own
    /// work, so it becomes a `CancellationError` and never reaches a person.
    static func transport(_ error: URLError) -> any Error {
        error.code == .cancelled ? CancellationError() : ASCError.transportFailed(underlying: error)
    }

    static func from(status: Int, data: Data, response: HTTPURLResponse) -> ASCError {
        let details = (try? JSONDecoder().decode(ASCErrorEnvelope.self, from: data))?.errors ?? []
        switch status {
        case 401: return .unauthorized(details: details)
        case 403: return .forbidden(details: details)
        case 404: return .notFound(details: details)
        case 409: return .conflict(details: details)
        case 422: return .unprocessable(details: details)
        case 429: return .rateLimited(rateLimit: RateLimit(response: response), details: details)
        case 500 ... 599: return .serverError(status: status, details: details)
        default: return .unexpectedStatus(status: status, details: details, body: data)
        }
    }

    public var details: [ASCErrorDetail] {
        switch self {
        case let .unauthorized(details), let .unauthorizedIndividualKey(details),
             let .forbidden(details), let .notFound(details),
             let .conflict(details), let .unprocessable(details):
            details
        case let .rateLimited(_, details), let .serverError(_, details),
             let .unexpectedStatus(_, details, _):
            details
        case .notAnHTTPResponse, .decodingFailed, .transportFailed:
            []
        }
    }

    /// Retrying a 429, a 5xx or a dropped connection can work. Retrying a 403
    /// never will.
    public var isWorthRetrying: Bool {
        switch self {
        case .rateLimited, .serverError: true
        case let .transportFailed(underlying): underlying.isTransient
        default: false
        }
    }
}

extension URLError {
    /// A network fault a second attempt can get past. A refused certificate or
    /// an address nobody can parse fails the same way every time.
    var isTransient: Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
             .requestBodyStreamExhausted, .internationalRoamingOff, .dataNotAllowed:
            true
        default:
            false
        }
    }
}

extension ASCError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        guard let said = details.sentences else { return sentence }
        return LocalizedStringResource("\(sentence) App Store Connect said: \(said)", bundle: .here)
    }

    /// What went wrong, as a whole sentence of its own.
    ///
    /// Apple's own words follow it as a separate sentence, and only when Apple
    /// sent some. Appending them to the end of this one left a sentence with
    /// no full stop whenever Apple sent nothing.
    private var sentence: LocalizedStringResource {
        switch self {
        case .notAnHTTPResponse:
            LocalizedStringResource("The answer did not come from App Store Connect. Try again.", bundle: .here)
        case .unauthorized:
            LocalizedStringResource("""
            App Store Connect refused the token. Check the Key ID, and check that \
            the clock on this Mac is right.
            """, bundle: .here)
        case .unauthorizedIndividualKey:
            LocalizedStringResource("""
            App Store Connect refused the token. This project names no Issuer ID, \
            so the token went out the way an individual key signs. A team key \
            needs its Issuer ID. Copy it from Users and Access, Integrations, \
            and put it in the project settings.
            """, bundle: .here)
        case .forbidden:
            LocalizedStringResource("""
            App Store Connect refused the request. Writing metadata needs a key \
            with the App Manager role or higher.
            """, bundle: .here)
        case .notFound:
            LocalizedStringResource("""
            App Store Connect cannot find what ASCKit asked for. Somebody may have \
            deleted it there. Read App Store Connect again.
            """, bundle: .here)
        case .conflict:
            LocalizedStringResource("""
            App Store Connect refused the change. The item is in a state that does not \
            allow it.
            """, bundle: .here)
        case .unprocessable:
            LocalizedStringResource("App Store Connect refused a value.", bundle: .here)
        case let .rateLimited(limit, _):
            Self.tooManyRequests(limit)
        case let .serverError(status, _):
            LocalizedStringResource(
                "App Store Connect answered with error \(status). Try again in a moment.", bundle: .here
            )
        case let .unexpectedStatus(status, _, _):
            LocalizedStringResource(
                "App Store Connect answered with status \(status), which ASCKit does not expect.", bundle: .here
            )
        case let .decodingFailed(underlying, _):
            if let field = Self.field(in: underlying) {
                LocalizedStringResource("""
                ASCKit cannot read the answer from App Store Connect. The field \(field) is not \
                what ASCKit expects. Check for a newer version of ASCKit.
                """, bundle: .here)
            } else {
                LocalizedStringResource("""
                ASCKit cannot read the answer from App Store Connect. \
                Check for a newer version of ASCKit.
                """, bundle: .here)
            }
        case let .transportFailed(underlying):
            ErrorMessage.network(underlying)
        }
    }

    /// What a 429 means, and when the person can try again.
    ///
    /// The wait comes first when App Store Connect named one, because it is the
    /// only part anybody can act on. The count is what is left of the hour.
    private static func tooManyRequests(_ limit: RateLimit?) -> LocalizedStringResource {
        if let wait = limit?.retryAfter {
            return LocalizedStringResource("""
            Too many requests to App Store Connect. \
            It says to try again in \(ErrorMessage.spellOut(wait)).
            """, bundle: .here)
        }
        if let remaining = limit?.remainingThisHour {
            return LocalizedStringResource("""
            Too many requests to App Store Connect. \
            \(remaining) requests left this hour.
            """, bundle: .here)
        }
        return LocalizedStringResource("Too many requests to App Store Connect.", bundle: .here)
    }

    /// The field the decoder stopped at, such as `data.attributes.name`.
    ///
    /// Swift's own description of a decoding error is a dump of coding keys and
    /// debug text, which is for a log. The path is the one part a person can
    /// take to a bug report.
    private static func field(in error: any Error) -> String? {
        guard let error = error as? DecodingError else { return nil }
        let path: [any CodingKey]
        switch error {
        case let .keyNotFound(key, context): path = context.codingPath + [key]
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            path = context.codingPath
        @unknown default: return nil
        }
        let written = path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        return written.isEmpty ? nil : written
    }
}

extension ASCError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}

public extension [ASCErrorDetail] {
    /// Apple's own words about a refusal, one sentence per detail.
    ///
    /// They stay in the language Apple wrote them in. Nil when Apple said
    /// nothing a person can read.
    var sentences: String? {
        let said = compactMap(\.sentence)
        return said.isEmpty ? nil : said.joined(separator: " ")
    }
}

extension ASCErrorDetail {
    /// One detail as a sentence that ends like one, and the field it is about.
    var sentence: String? {
        let field = pointer.map { String(localized: "The field is \($0).", bundle: .module) }
        guard let words = (detail ?? title ?? code)?.trimmingCharacters(in: .whitespaces),
              words.isEmpty == false
        else { return field }

        let closed = words.last.map { ".!?".contains($0) } == true ? words : words + "."
        return [closed, field].compactMap(\.self).joined(separator: " ")
    }
}
