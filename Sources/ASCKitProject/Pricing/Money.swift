import Foundation

/// An amount of money, written in a file as a string.
///
/// A string and not a JSON number, because a JSON number decodes to a `Double`
/// and `4.99` is not 4.99 as a `Double`. That matters twice. A price that does
/// not round-trip comes back out of the file as something else. And a target
/// price is compared against a whole ladder to find the step above it, which
/// needs an exact comparison that a `Double` cannot give.
///
/// This is the same class of decision as counting a keyword field in characters
/// rather than in bytes: the obvious type is the wrong one, and the store is
/// where you find out.
///
/// The written form is canonical rather than kept as typed. `4.90` and `4.9`
/// are one price, so they read back as one string, and rewriting a file does
/// not move the change plan's digest.
public struct Money: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let amount: Decimal

    public init(_ amount: Decimal) {
        self.amount = amount
    }

    /// Nil for anything that is not a plain decimal number, a currency symbol
    /// and a thousands separator included. The file holds the number, and the
    /// currency comes from the territory.
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return nil }
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        guard let parsed = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        amount = parsed
    }

    /// The canonical written form, which is what goes in a file and in the
    /// digest.
    public var description: String { "\(amount)" }

    /// The amount as a person reads it, in their own locale: $12.13 in the
    /// US, 12,13 € in Germany. The currency sets the number of decimals.
    public func formatted(currency code: String?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let code else { return amount.formatted(.number.locale(locale)) }
        return amount.formatted(.currency(code: code).locale(locale))
    }

    public var isPositive: Bool { amount > 0 }

    /// Whether this amount ends in `.99`.
    ///
    /// `.99` is the ending ASCKit lands on. A currency with no minor unit,
    /// such as the yen, has no such ending, and answers false here for every
    /// amount.
    public var endsInNinetyNine: Bool { cents == 99 }

    /// Whether this amount ends in `.49`, the other ending ASCKit uses.
    public var endsInFortyNine: Bool { cents == 49 }

    /// The two decimals of a whole number of cents, or nil for an amount with
    /// more decimals than that.
    private var cents: Int? {
        var scaled = amount * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)
        guard whole == scaled else { return nil }
        return NSDecimalNumber(decimal: whole).intValue % 100
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }

    /// How far apart two amounts are, for saying how much rounding added.
    public func distance(to other: Money) -> Decimal {
        abs(amount - other.amount)
    }

    /// This amount scaled by a curve's multiplier.
    ///
    /// The multiplier crosses into `Decimal` through its shortest written form
    /// rather than through `Decimal(Double)`, which carries the `Double`'s own
    /// error in. Without that, the same curve could reach two different price
    /// points on two machines.
    public func scaled(by multiplier: Double) -> Money {
        let exact = Decimal(string: "\(multiplier)", locale: Locale(identifier: "en_US_POSIX"))
        return Money(amount * (exact ?? Decimal(multiplier)))
    }
}

extension Money: ExpressibleByStringLiteral {
    public typealias StringLiteralType = StaticString

    /// An amount written straight into source: `let price: Money = "4.99"`.
    ///
    /// A `StaticString`, so only a literal can reach this. An amount that
    /// arrives at runtime, out of a file or from a person, has to go through
    /// `init?(string:)` and be answered for, because a bad one there is a state
    /// to report rather than a mistake somebody can read on the line above.
    public init(stringLiteral value: StaticString) {
        guard let parsed = Money(string: "\(value)") else {
            preconditionFailure("\(value) is not an amount")
        }
        self = parsed
    }
}

extension Money: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let written = try container.decode(String.self)
        guard let parsed = Money(string: written) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: """
                \"\(written)\" is not an amount. Write it as a string of \
                digits and a decimal point, such as \"4.99\".
                """
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
