import ASCKitAPI
import Foundation

/// The device classes under one heading, in the order the table lists them.
///
/// App Store Connect puts a tab over each of these, and the screenshots page
/// puts a heading over each instead, so the whole page scrolls as one.
public struct DeviceClassGroup: Sendable, Hashable, Identifiable {
    public var id: String { heading }
    public let heading: String
    public let deviceClasses: [DeviceClass]
}

public extension DeviceClass {
    /// Gathers device classes under their headings, keeping the order they
    /// arrive in.
    static func grouped(_ deviceClasses: [DeviceClass]) -> [DeviceClassGroup] {
        var headings: [String] = []
        var members: [String: [DeviceClass]] = [:]

        for deviceClass in deviceClasses {
            if members[deviceClass.heading] == nil { headings.append(deviceClass.heading) }
            members[deviceClass.heading, default: []].append(deviceClass)
        }
        return headings.map { DeviceClassGroup(heading: $0, deviceClasses: members[$0] ?? []) }
    }
}
