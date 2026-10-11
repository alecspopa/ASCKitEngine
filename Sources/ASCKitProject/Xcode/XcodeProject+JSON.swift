import Foundation

extension XcodeProject {
    /// The JSON project format Xcode 27.2 writes.
    ///
    /// It carries the same values as the property list one under different
    /// names, and in a shape that reads like the Xcode window: one list of
    /// targets, each with its own settings, rather than a flat table of objects
    /// pointing at each other by identifier.
    static func readJSON(
        _ data: Data,
        at url: URL,
        sourceRoot: URL
    ) throws -> XcodeProject {
        // JSON5, not JSON. Xcode writes a comma after the last item of every
        // list, and a person may leave a comment in the file. `JSONSerialization`
        // reads both with this option, and `JSONDecoder` reads neither.
        guard
            let root = try? JSONSerialization.jsonObject(
                with: data, options: [.json5Allowed]
            ) as? [String: Any],
            root["files"] != nil || root["targets"] != nil
        else {
            throw XcodeProjectError.notAProject(url: url)
        }

        // The configuration Xcode builds when nobody says which. Release in
        // every project from a template, and what reaches the App Store.
        let configuration = root["default-configuration"] as? String ?? "Release"
        let projectSettings = settings(root["build-settings"], for: configuration)
        let targets = (root["targets"] as? [[String: Any]]) ?? []

        return XcodeProject(
            url: url,
            knownRegions: languages(root["localizations"]),
            apps: targets.compactMap {
                app(
                    target: $0,
                    inheriting: projectSettings,
                    configuration: configuration,
                    sourceRoot: sourceRoot
                )
            }
        )
    }

    /// The languages a JSON project ships. The old format wrote one list, and
    /// this one writes the development language apart from the rest.
    private static func languages(_ localizations: Any?) -> [String] {
        guard let localizations = localizations as? [String: Any] else { return [] }
        return languages(
            development: localizations["development"] as? String,
            supported: (localizations["supported"] as? [String]) ?? []
        )
    }

    /// The languages a project ships, the one it is written in first.
    ///
    /// A listing takes its source language from the front of this list, so an
    /// app whose development language is `en` gets an English listing however
    /// far down `knownRegions` Xcode wrote `en`.
    ///
    /// `RegionMatch` keeps the order it is given, so a person sees the rest in
    /// the order the project file writes them.
    static func languages(development: String?, supported: [String]) -> [String] {
        var seen: Set<String> = []
        return ([development].compactMap(\.self) + supported)
            // `Base` is where the storyboards live, not a language somebody
            // reads the app in.
            .filter { $0 != "Base" && seen.insert($0).inserted }
    }

    private static func app(
        target: [String: Any],
        inheriting projectSettings: [String: String],
        configuration: String,
        sourceRoot: URL
    ) -> App? {
        guard
            (target["kind"] as? String ?? "native") == "native",
            productType(of: target) == "com.apple.product-type.application",
            let name = target["name"] as? String
        else {
            return nil
        }

        var resolved = projectSettings
        resolved.merge(
            settings(target["build-settings"], for: configuration),
            uniquingKeysWith: { _, target in target }
        )
        return app(named: name, settings: resolved, sourceRoot: sourceRoot)
    }

    /// What a target builds, as the old format spelled it.
    ///
    /// `product-type` drops the prefix every Apple product type shares, so
    /// `application` there is `com.apple.product-type.application` here.
    /// `full-product-type` holds one that does not start with that prefix.
    private static func productType(of target: [String: Any]) -> String? {
        if let short = target["product-type"] as? String {
            return "com.apple.product-type.\(short)"
        }
        return target["full-product-type"] as? String
    }
}
