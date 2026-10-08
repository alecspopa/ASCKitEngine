import ArgumentParser
import ASCKitProject
import Foundation

/// Reads which languages this project leaves to App Store Connect, ignores one
/// more, or takes an ignore back.
///
/// It goes through `IgnoredLocales` in the package, which is what the app
/// writes through as well, so a language ignored in the terminal is ignored in
/// the window.
struct Ignore: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ignore",
        abstract: "Read which languages are ignored, ignore one, or stop ignoring one.",
        discussion: """
        With no language it reads what is ignored now and changes nothing.

        An app is often built in more languages than its store page is written in. \
        The Xcode project ships Romanian, and nobody is going to write a Romanian store page. \
        Left alone, that language is a warning on every run.

        An ignored language stays in locales, so the check still knows the app is built in it \
        and stops asking for a listing to match. Nothing is written for it, nothing is checked \
        about it, and the window shows it at the bottom of the languages marked Ignored.

        Ignoring moves that language's text and screenshots to the Trash, in every version \
        folder. Stopping the ignore writes no file back, so run asckit pull to read the words \
        down from App Store Connect again.

        ASCKit never makes a language on App Store Connect. A language the store has no page \
        for is one a push writes nothing in, whether or not it is ignored.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Argument(help: ArgumentHelp(
        "The language to ignore, such as ro. Leave it out to read the list.",
        valueName: "locale"
    ))
    var locale: String?

    @Flag(name: .long, help: "Stop ignoring the language instead of ignoring it.")
    var stop = false

    func run() throws {
        let project = try options.loadProject()

        guard let locale else {
            guard stop == false else {
                print("Name the language to stop ignoring.")
                throw ExitCode.failure
            }
            list(project)
            return
        }

        let config = try IgnoredLocales.set(stop == false, locale: locale, in: project)

        if stop {
            print("\(locale) is written again. This project writes \(config.writtenLocales.count) languages.")
            print("It has no file here. Run asckit pull to read its words down from App Store Connect.")
        } else {
            print("\(locale) is ignored. This project writes \(config.writtenLocales.count) languages.")
            print("Its text and screenshots moved to the Trash.")
        }
    }

    private func list(_ project: Project) {
        let config = project.config

        guard config.ignoredLocales.isEmpty == false else {
            print("Nothing is ignored. This project writes \(config.locales.joined(separator: ", ")).")
            return
        }

        print("Ignored:")
        for locale in config.ignoredLocales {
            let name = StoreLocale.englishName(for: locale)
            print("  \(locale)\(name.map { " (\($0))" } ?? "")")
        }
        print("")
        print("Written: \(config.writtenLocales.joined(separator: ", "))")
        print("Stop ignoring one with asckit ignore --stop <locale>.")
    }
}
