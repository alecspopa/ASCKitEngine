/// The files of one set, with the place and the set they are in. What the
/// validator checks for a treatment or a custom product page.
struct PlacedFiles<File> {
    let place: LibraryContentPlace
    let slot: ScreenshotSlot
    let files: [File]
}

extension ExperimentSlot {
    func placed<File>(_ files: [File]) -> PlacedFiles<File> {
        PlacedFiles(place: place, slot: ScreenshotSlot(locale: locale, deviceClassID: deviceClassID), files: files)
    }
}

extension CustomPageSlot {
    func placed<File>(_ files: [File]) -> PlacedFiles<File> {
        PlacedFiles(place: place, slot: ScreenshotSlot(locale: locale, deviceClassID: deviceClassID), files: files)
    }
}
