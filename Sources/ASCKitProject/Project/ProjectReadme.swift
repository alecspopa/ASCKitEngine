import Foundation

/// The README that goes in a project folder.
///
/// It says what the folder is and how to use it. That never changes, so the
/// text is fixed and ASCKit writes it without asking.
///
/// It deliberately holds no limits, pixel sizes or locale codes. Those change,
/// and a second copy of a number that changes is a number that ends up wrong.
/// `asckit check` reports them precisely and needs no app, so the README points
/// at that instead of repeating it.
enum ProjectReadme {
    /// The whole thing, in the order somebody reads it.
    ///
    /// Written in parts only because one string of four hundred lines is
    /// one thing nobody can find their way around.
    static let text = [listing, ProjectReadmeProducts.text, rest].joined(separator: "\n\n")

    /// What the folder is, and the listing text in it.
    private static let listing = """
    # This folder

    An App Store listing, kept as files. ASCKit reads it, checks it against what
    App Store Connect will accept, and uploads it when you say so.

    Editing a file changes what *would* go up. Nothing is uploaded until a person
    presses the button in ASCKit or runs `asckit push`.

    ## What is where

    ```
    asckit.json                  which app this is, and which languages
    inbox/                       new screenshots wait here before they go in
    cache/                       what ASCKit read from the store. Not in git
    products/
      com.example.pro.json       one file per in-app purchase
      silenced.json              product warnings somebody has read
    versions/
      1.0/
        version-data/
          en-US.json             one file per language, all the listing text
          de-DE.json
        screenshots/
          en-US/
            iphone-6.9/
              01-hero.png        the number is the order Apple shows them in
              02-shared.png
            ipad-13/
          de-DE/
    history/                     what was pushed, and when
    ```

    Version folders are named after the version string on App Store Connect,
    such as `1.0` or `2.3.1`. The newest one is the one being worked on.

    ASCKit reads the version off App Store Connect every time it opens this
    project, so a version somebody added in the web page shows up here without
    anybody asking for it. A version with no folder is reported, with a button
    that makes the folder.

    A project written before this folder was renamed has an `app-information`
    folder instead of `version-data`. ASCKit reads whichever one is there and
    renames nothing.

    ## asckit.json

    | Key | What it is |
    | --- | --- |
    | `bundleId` | Which app on App Store Connect this folder describes. |
    | `keyId` | The name of an API key. The key itself is in `~/.appstoreconnect/private_keys`. |
    | `issuerId` | The team the key belongs to. Left out for an individual key. |
    | `sourceLocale` | The language the listing is written in. Every translation is read against it. |
    | `locales` | Every language the app ships in. |
    | `ignoredLocales` | The languages in that list the store page is not written in. \
    Nothing is written for them and nothing is checked about them. |
    | `deviceClasses` | Which screenshot sizes this app ships. |
    | `platform` | Which version this folder writes when an app sells on more than one: \
    `ios`, `macos`, `tvos` or `visionos`. |
    | `versionsPath` | Where the version folders live. Default `versions`. |
    | `historyPath` | Where the push records live. Default `history`. |

    The `.p8` private key never goes in this folder. `keyId` and `issuerId` are
    names, not secrets. The key is `AuthKey_<keyId>.p8` in
    `~/.appstoreconnect/private_keys`, the folder Apple's tools use. ASCKit and
    `asckit` both read it there.

    ## A language file

    One file per language, named after the language: `de-DE.json`. The file name
    decides which language it is. A `locale` field inside that disagrees with the
    file name is reported as a problem rather than quietly followed.

    ```json
    {
      "locale": "de-DE",
      "status": "needs_human",
      "fields": {
        "name": "Beispiel",
        "subtitle": "Geteilte Vorratsliste",
        "keywords": "haushalt,vorrat",
        "description": "…",
        "whatsNew": "…",
        "promotionalText": "…",
        "supportUrl": "https://example.com/support",
        "marketingUrl": "https://example.com",
        "privacyPolicyUrl": "https://example.com/privacy"
      }
    }
    ```

    ### An empty string is not the same as a missing field

    Writing `"subtitle": ""` blanks the subtitle on the store. To leave a field
    alone, take the key out of the file.

    ### status

    | Value | Means | Publishes |
    | --- | --- | --- |
    | `draft` | Started, not finished. | no |
    | `needs_human` | A machine wrote it, nobody has read it. | no |
    | `ai_approved` | A machine wrote it and checked its own work. | yes |
    | `approved` | A person read it. | yes |

    `ai_approved` and `approved` behave the same way. They are kept apart so the
    file can answer the question somebody asks when a listing goes out wrong: who
    read this? Only a person sets `approved`, using the button in ASCKit.

    ### Words of its own

    Every language holds its own words. Rewriting the source language changes
    nothing in any other file, and ASCKit says nothing about the others.

    What it does say is where a language has no words of its own. A field the
    source language fills and this one leaves empty is a warning, and so is a
    field holding the source language's words unchanged. Web addresses are left
    out of both, because the same address in every language is the answer.
    """

    /// Screenshots, checking, and the note for an AI.
    private static let rest = """
    ## Screenshots

    One folder per language, one folder inside that per device class:

    ```
    screenshots/en-US/iphone-6.9/03-shopping-iPhone-6.9-en_US.png
    ```

    Every file is named that way, and ASCKit writes the name itself:

    ```
    03-shopping-iPhone-6.9-en_US.png
    |  |        |          |
    |  |        |          the language, as asckit.json names it
    |  |        the device class
    |  what the screenshot shows
    where it goes in the set
    ```

    The number is the order Apple shows them in, counting from `01`. What the
    screenshot shows is the part that matters across languages: ASCKit matches
    on it, and reports it when German has a picture English does not.

    The folder decides the device class and the language a name says. A file
    copied out of another language is renamed as it lands, so a name can never
    say one language while the folder says another.

    The name goes to App Store Connect with the image, and the next push looks
    for it there. That is how ASCKit knows an image on App Store Connect is one
    of these rather than one somebody added in the web page.

    Do not renumber by hand. Renaming `02` to `01` while `01` still exists loses
    a file. Ask ASCKit to reorder the set instead.

    ### Screenshots a language does not have its own of

    App Store Connect shows the source language's screenshots to anybody whose
    language has none, one device class at a time. For a language that reads the
    same words as the source, such as `en-GB` beside `en-US`, say so in
    asckit.json and the empty folder stops being an error:

    ```json
    "usesSourceScreenshots": { "en-GB": ["ipad-13"] }
    ```

    In the app it is a checkbox in each device class heading on a language's
    Screenshots page. It holds for every version.

    A language that reads different words gets no checkbox. It needs pictures
    with its own words in them, so an empty folder is a warning, and so is a
    folder holding the source language's files byte for byte.

    The header and search results art works the same way. A language listed
    here shows the source language's files, and the push places the assets
    already in the library, so nothing goes up twice:

    ```json
    "usesSourceCreative": ["en-AU", "en-CA", "en-GB"]
    ```

    In the app it is a checkbox on a language's Header and Search Results
    section. Files in the language's own folder win.

    ### inbox

    Put a new screenshot in `inbox/` first, then ask ASCKit to add it. ASCKit
    checks the name, the pixel size and the alpha channel, puts the file in the
    right folder, and numbers the whole set again. A file named any other way is
    refused, in the window and in the terminal alike.

    The name of a waiting file says where it goes:

    ```
    03-shopping-iPhone-6.9-en_US.png
    |  |        |          |
    |  |        |          the language, `en_US` or `en`
    |  |        the device class, as asckit.json names it
    |  what the screenshot shows
    where it goes in the set
    ```

    That file is filed as `en-US/iphone-6.9/03-shopping-iPhone-6.9-en_US.png`.
    The name stays with the file, so a later import replaces it rather than
    filing the same picture twice.

    An open project window watches this folder. Drop images in, and the window
    shows where each one is going. Nothing is asked. In the terminal the same
    thing is `asckit inbox`, which prints where each file goes, and
    `asckit inbox --file`, which moves them in.

    The folder exists because ASCKit runs in the macOS sandbox and can only read
    the folder you gave it. A file on the Desktop is out of reach, and a file in
    `inbox/` is not.

    Nothing in `inbox/` is committed. The folder has its own `.gitignore`, and
    git adds those rules to the ones in the repository's `.gitignore` rather
    than replacing them, so the repository needs no line for this.

    ### A device class this project does not list yet

    `deviceClasses` in asckit.json says which screenshot sizes this app ships,
    and a waiting file for any other one is refused. That is the right answer
    the first time an iPad screenshot lands in an iPhone-only project by
    mistake.

    It is the wrong answer the first time the app starts shipping on iPad. The
    images are made, they are named, they are a size Apple takes, and the only
    thing missing is the line in asckit.json. So the waiting files are what adds
    it:

    ```
    asckit inbox --adopt-devices           # add what the waiting names ask for
    asckit inbox --adopt-devices --file    # add it, then file the images
    ```

    In the app, the inbox sheet names the device class it cannot file for and
    offers a button that adds it. On the MCP server the same thing is
    `adopt_devices`. None of the three takes a device class you type: a named
    image of the right size is the evidence that the app ships on that device,
    and a name nobody can read is still a rename.

    Adding a device class also makes the folder its screenshots go in, one per
    language. Every language then needs its own set for it, or
    `usesSourceScreenshots` to say it shows the source language's.
    `asckit check` lists the ones still empty.

    ### A waiting file with an alpha channel

    App Store Connect refuses a screenshot that carries one, so ASCKit refuses
    it here rather than at the end of a push. Most design tools write a channel
    into artwork that is fully opaque, which makes this the one refusal where
    the picture is already right.

    So the file is written again without the channel, rather than exported a
    second time:

    ```
    asckit inbox --clear-alpha           # write them again with no channel
    asckit inbox --clear-alpha --file    # write them again, then file them
    ```

    In the app, the inbox sheet counts the waiting files that carry a channel
    and offers a button that clears them.

    The image is painted onto white first, because a picture that really is part
    transparent has to land on some colour once the channel goes. The file as it
    arrived goes to the Trash, since this changes its pixels and the copy in
    `inbox/` may be the only one anybody has.

    Only a file the device class would otherwise take is offered. One of the
    wrong size stays refused after the channel goes, and clearing it would
    change the picture for nothing.

    ## Checking it

    ```
    asckit check
    ```

    Every length limit, accepted pixel size, missing field and untranslated
    screenshot, reported against this project. No app and no credentials needed, so it works
    in a git hook.

    Those numbers live in ASCKit rather than in this file, because they change
    and this file does not.

    ### Warnings you have already read

    ```
    asckit silence              # read what is silenced, numbered
    asckit silence --all        # silence every warning this version has now
    asckit silence --show 2     # bring one back, by its number in that list
    asckit silence --clear      # bring them all back
    ```

    A silence hides a warning about the listing in one version. It goes in
    silenced.json beside the version. That file goes into git with the listing it
    is about. A check of 1.1 shows the warning again.

    A silence hides a warning about an in-app purchase in every version. It goes
    in products/silenced.json. A check of every version reads that file. The
    warning stays hidden in 1.1 too.

    The list numbers the version silences first, then the product silences.

    Errors are never silenced.

    ### The language beside this one got the newer screenshots

    ```
    asckit copy-screenshots              # read what could be copied, numbered
    asckit copy-screenshots --accept 1   # make one copy, by its number
    asckit copy-screenshots --all        # make every copy in the list
    ```

    es-ES and es-MX read the same pictures, so a new export that landed in one
    of them belongs in the other. Which one is newer is the date on the files.

    Only inside one language. The en-US screenshots are English pictures, and a
    Spanish listing showing them is what usesSourceScreenshots is for instead.

    A copy makes the two folders match. Whatever the older language held goes to
    the Trash.

    A copy is also written into asckit.json, because it says how the app is
    translated:

    ```json
    "copiesScreenshotsFrom": { "es-ES": { "ipad-13": "es-MX" } }
    ```

    It holds for every version. Pictures filed into es-MX from `inbox/` go into
    es-ES too, and a new version folder starts with the same copy. Only a newer
    es-MX set is copied, so an export that landed in es-ES stays there. What
    es-ES held goes to the Trash, and the report names the copy.

    In the app, a checkbox in the device class heading turns it off. The files
    stay where they are.

    ## For an AI working in this folder

    Run `asckit check` after editing, and fix what it reports.

    If ASCKit is open, it also runs a local MCP server. Connected to that, the
    checks above become tools you can call, and `describe_project` answers with
    this project's own languages, device classes and limits.

    Two things to be careful of:

    - Take a key out of `fields` to leave it alone. An empty string blanks it on
      the store.
    - Set `ai_approved`, not `approved`. `approved` means a person read it.
    """
}
