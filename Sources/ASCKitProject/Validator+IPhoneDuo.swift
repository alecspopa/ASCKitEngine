import ASCKitAPI
import Foundation

extension Validator {
    /// From April 2027, App Store Connect takes no submission of an iPhone app
    /// without iPhone Duo screenshots. A warning until then, so a project has
    /// time to make them, and it can be silenced.
    func validateIPhoneDuo() -> [Problem] {
        let listed = config.resolvedDeviceClasses
        let shipsIPhone = listed.contains { $0.family == "iPhone" && $0.screenshotPlacementType == .appScreenshot }
        guard shipsIPhone, listed.contains(.iPhoneDuo) == false else { return [] }

        return [Problem(
            severity: .warning,
            area: .configuration,
            message: LocalizedStringResource(
                "App Store Connect needs iPhone Duo screenshots for every submission from April 2027.",
                bundle: .here
            ),
            fix: LocalizedStringResource(
                "Add \(DeviceClass.iPhoneDuo.id) to the device classes, then add its screenshots.",
                bundle: .here
            ),
            deviceClassID: DeviceClass.iPhoneDuo.id,
            path: Project.defaultConfigName,
            kind: .iPhoneDuoMissing
        )]
    }
}
