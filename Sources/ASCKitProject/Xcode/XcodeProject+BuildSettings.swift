import Foundation

extension XcodeProject {
    /// The release configuration's settings, or the last one when there is no
    /// configuration by that name.
    ///
    /// Release rather than debug, because the version and the bundle identifier
    /// that reach the App Store are the release ones.
    static func settings(
        ofConfigurationList id: Any?,
        in objects: [String: [String: Any]]
    ) -> [String: String] {
        guard
            let listID = id as? String,
            let list = objects[listID],
            let configIDs = list["buildConfigurations"] as? [String]
        else {
            return [:]
        }

        let configs = configIDs.compactMap { objects[$0] }
        let wanted = list["defaultConfigurationName"] as? String ?? "Release"
        let chosen = configs.first { $0["name"] as? String == wanted } ?? configs.last

        guard let settings = chosen?["buildSettings"] as? [String: Any] else { return [:] }
        return settings.compactMapValues { $0 as? String }
    }

    /// The build settings a JSON project applies to one configuration.
    ///
    /// The old format wrote a whole table of settings per configuration. This
    /// one writes a single table and puts the condition in the key, as
    /// `SWIFT_VERSION[config=Debug]`. A key with no condition applies to every
    /// configuration, and a key naming this configuration wins over it.
    static func settings(_ raw: Any?, for configuration: String) -> [String: String] {
        guard let raw = raw as? [String: Any] else { return [:] }

        var plain: [String: String] = [:]
        var conditional: [String: String] = [:]

        for (key, value) in raw {
            guard
                let text = settingValue(value),
                let setting = settingName(of: key, for: configuration)
            else {
                continue
            }

            if setting.conditional {
                conditional[setting.name] = text
            } else {
                plain[setting.name] = text
            }
        }

        return plain.merging(conditional, uniquingKeysWith: { _, conditional in conditional })
    }

    /// The name a build setting key carries, and whether the key names this
    /// configuration to get it.
    ///
    /// Nil for a key held back by any other condition, such as
    /// `[sdk=iphoneos*]`. Which SDK the app is built for is not known here, so
    /// taking one of those values would be a guess. The old format wrote the
    /// same conditions into the same kind of key, and this skips those too.
    private static func settingName(
        of key: String,
        for configuration: String
    ) -> (name: String, conditional: Bool)? {
        guard let start = key.firstIndex(of: "[") else { return (key, false) }

        // `NAME[a=b][c=d]` splits into `a=b` and `c=d`, each still holding the
        // bracket that opened it.
        for condition in key[start...].split(separator: "]") {
            let parts = condition.dropFirst().split(separator: "=", maxSplits: 1)
            guard
                parts.count == 2,
                parts[0] == "config",
                matches(String(parts[1]), configuration)
            else {
                return nil
            }
        }

        return (String(key[key.startIndex ..< start]), true)
    }

    /// A condition value against a configuration name. Xcode takes a `*` in
    /// one, and `[config=*]` is the form that turns up.
    private static func matches(_ pattern: String, _ configuration: String) -> Bool {
        guard pattern.hasSuffix("*") else { return pattern == configuration }
        return configuration.hasPrefix(pattern.dropLast())
    }

    /// One build setting value.
    ///
    /// The JSON format writes a list where the old one wrote a single string
    /// with spaces in it, and everything reading a setting here wants the
    /// string. Any other kind of value is left out. Xcode writes a string or a
    /// list of strings and nothing else, so one has been written by hand.
    private static func settingValue(_ value: Any) -> String? {
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.joined(separator: " ") }
        return nil
    }
}
