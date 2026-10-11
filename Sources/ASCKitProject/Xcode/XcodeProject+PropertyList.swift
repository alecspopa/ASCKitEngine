import Foundation

extension XcodeProject {
    static func readPropertyList(
        _ data: Data,
        at url: URL,
        sourceRoot: URL
    ) throws -> XcodeProject {
        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard
            let root = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: &format
            ) as? [String: Any],
            let objects = root["objects"] as? [String: [String: Any]],
            let rootID = root["rootObject"] as? String,
            let project = objects[rootID]
        else {
            throw XcodeProjectError.notAProject(url: url)
        }

        let projectSettings = settings(ofConfigurationList: project["buildConfigurationList"], in: objects)
        let targetIDs = (project["targets"] as? [String]) ?? []

        return XcodeProject(
            url: url,
            // `knownRegions` holds the development language as well, in the
            // place it was added rather than at the front. `developmentRegion`
            // is what says which of them it is.
            knownRegions: languages(
                development: project["developmentRegion"] as? String,
                supported: (project["knownRegions"] as? [String]) ?? []
            ),
            apps: targetIDs.compactMap {
                app(id: $0, in: objects, inheriting: projectSettings, sourceRoot: sourceRoot)
            }
        )
    }
}
