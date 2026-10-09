import Testing
@testable import ASCKitProject

struct ExperimentSlotTests {
    let slot = ExperimentSlot(experiment: "Fall", treatment: "Treatment A", locale: "en-US", deviceClassID: "iphone69")

    @Test func namesTheTreatmentTheWayCreativeIsKeyed() {
        #expect(slot.treatmentKey == "Fall/Treatment A")
        #expect(slot.treatmentKey == ExperimentContent.creativeKey(experiment: "Fall", treatment: "Treatment A"))
    }

    @Test func namesTheFolderBelowTheExperimentsFolder() {
        #expect(slot.path == "Fall/Treatment A/en-US/iphone69")
    }
}
