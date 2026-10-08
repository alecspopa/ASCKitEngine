# ASCKitEngine

App Store Connect makes you type the same listing once per language. Each one
needs its own title, subtitle, keyword field, description and screenshots. Each
is a separate web form. The character counter only appears after you paste.

Three things are missing from that. You cannot review a change before it goes
out. You cannot compare what you are about to publish against what is live. And
nothing tells you that the German subtitle is still the English one.

ASCKitEngine keeps the listing in files you can put in git. It reads those
files, checks them, shows exactly what will change, and writes it to App Store
Connect. It is the engine of the ASCKit Mac app, and it ships the `asckit`
command line tool.

## Why the source is public

This package holds your App Store Connect key and every request that goes to
Apple. The source is public so that you can check what it does with them:

- `PrivateKeyStore` is the only code that reads or writes the `.p8` file.
- `ASCKitAPI` is the only code that opens a network connection. It talks to
  `api.appstoreconnect.apple.com`, and to the upload addresses that App Store
  Connect returns for an image.
- Nothing sends data anywhere else. There is no analytics code and no
  telemetry.

The source is available under the PolyForm Noncommercial License 1.0.0. It is
not an open source license as the Open Source Initiative defines one. See
[License](#license).

## The parts

| | |
| --- | --- |
| `Sources/ASCKitAPI` | Talks to Apple. No file system, no configuration. |
| `Sources/ASCKitProject` | Reads configuration and content. Never opens a socket. |
| `Sources/asckit` | The command line tool. |
| `Sources/ASCKitTestSupport` | One fake App Store Connect for the tests. |

`ASCKitProject` depends on `ASCKitAPI`, and `ASCKitAPI` depends on nothing in
this package. Every rule lives here, so the command line tool and the app cannot
answer the same question differently:

- `Project.open` decides which folders can be opened at all.
- `NewProject.read` decides which app a new project is for, and which languages.
- `PushSession` reads App Store Connect, works out the plan, writes it, and
  files the record of what it wrote.

## Getting started

Build the command line tool:

```
swift build -c release
```

The binary lands at `.build/release/asckit`. It is called `asckit` and not
`asc` because Homebrew already ships an `asc`, which is also an App Store
Connect command line tool.

## The key

Make an API key in App Store Connect, under Users and Access, Integrations,
with the **App Manager** role. Developer is not enough. It reads fine and then
returns 403 on the first write, so a `pull` that works does not mean a push
will.

The command line tool reads the `.p8` from disk. It searches the same four
folders Apple's own tools use, in the same order. A key that already works for
`altool` works here:

```
./private_keys
~/private_keys
~/.private_keys
~/.appstoreconnect/private_keys
```

Put it in the last of those and give it the name Apple gave it:

```
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

`ASCKIT_PRIVATE_KEY` overrides all of that with an explicit path.

The ASCKit app reads the same file. It is sandboxed, so it asks once for the
folder that holds the keys. A `.p8` picked from somewhere else is checked with
`PrivateKeyStore.readKey`, then written into that folder with
`PrivateKeyStore.install`, readable by the owner only. Both are in this package,
so you can read every line that touches the key.

The key never belongs in a project. Only the key id and the issuer id do, and
those are identifiers rather than secrets.

## A project

A project is a folder inside that app's own repository, beside the
`.xcodeproj`. ASCKit holds none of it.

```
.asckit/
├── asckit.json
├── asset-library.json
├── inbox/
├── history/
└── versions/
    └── 1.0/
        ├── silenced.json
        ├── version-data/
        │   ├── en-US.json
        │   └── de-DE.json
        └── screenshots/
            └── en-US/
                ├── iphone-6.9/
                │   ├── 01-running-low.png
                │   └── 02-shared.png
                └── ipad-13/
```

A version folder can also hold `previews/` and `creative/`. See "The asset
library" below.

The folder is called `version-data` rather than `app-information`, because App
Store Connect has a tab called App Information and this folder holds more than
that tab does. A project written before the rename has an `app-information`
folder. ASCKit reads whichever one is there and renames nothing.

`inbox/` is where a screenshot waits before ASCKit files it. It has its own
`.gitignore`, and git adds those rules to the repository's rather than replacing
them, so nothing has to be added to the repository's own `.gitignore`.

The name of a waiting file says where it goes, so a folder of screenshots can
be dropped in one go and nothing has to be asked:

```
03-shopping-iPhone-6.9-en_US.png
|  |        |          |
|  |        |          the language, `en_US` or `en`
|  |        the device class, as asckit.json names it
|  what the screenshot shows
where it goes in the set
```

That file is filed as `en-US/iphone-6.9/03-shopping-iPhone-6.9-en_US.png`.
The full inbox name stays with the file, so a later import can replace it.

An open project window reads that folder when it opens and watches it after
that. Drop images in, and the window shows where each one is going. In the
terminal the same thing is `asckit inbox`, which says where each file goes, and
`asckit inbox --file`, which moves them in. Both read the name through
`ScreenshotNaming` in the package, so a file cannot land in one folder in the
window and another in the terminal.

A file whose name does not say all of that stays where it is, with the reason
beside it. So does one whose pixel size the device class in its name would not
take.

Screenshots are per language **and** per device class, because App Store Connect
stores them that way. Language comes first in the path because that is how you
review a set: "is the German listing complete" should be one folder.

The file name decides the order, and every file is named the same way:
`03-shopping-iPhone-6.9-en_US.png`. The number is the position, then what the
screenshot shows, then the device class and the language. ASCKit writes that
name, gives it to App Store Connect with the image, and looks for it there on
the next push. What the screenshot shows stays in English in every language.

### `asckit.json`

```json
{
  "bundleId": "com.example.MyApp",
  "keyId": "XXXXXXXXXX",
  "issuerId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "sourceLocale": "en-US",
  "deviceClasses": ["iphone-6.9", "ipad-13"],
  "locales": ["en-US", "en-GB", "de-DE", "ja", "ro"],
  "ignoredLocales": ["ro"],
  "usesSourceScreenshots": { "en-GB": ["ipad-13"] }
}
```

Leave `issuerId` out for an individual key. The language list and the device
classes live here, so every project sets its own.

`ignoredLocales` names the languages the app is built in and the store page is
not. See "Languages ASCKit leaves alone" below.

`usesSourceScreenshots` names the languages that show the source language's
screenshots, one device class at a time. Only a language that reads the same
words as the source belongs there. See "Screenshots a language does not have
its own of" below.

### One file per language, under `version-data`

```json
{
  "locale": "de-DE",
  "status": "needs_human",
  "fields": {
    "name": "...",
    "subtitle": "...",
    "keywords": "...",
    "description": "...",
    "supportUrl": "...",
    "privacyPolicyUrl": "..."
  }
}
```

`status` is `draft`, `needs_human`, `ai_approved` or `approved`, and **only
`ai_approved` and `approved` are ever published**. `ai_approved` means a machine
wrote it and checked its own work. `approved` means a person read it, and only a
person sets it. They publish the same way. They are kept apart so the file
answers the question somebody asks when a listing goes out wrong: who read this?

Every language holds its own words, so rewriting the source language changes
nothing in any other file. What ASCKit reports is a field the source language
fills and this one leaves empty, and a field holding the source language's words
unchanged.

A field that is not there is left alone on App Store Connect. A field set to an
empty string blanks it. That difference is deliberate, and `check` refuses an
empty required field so you cannot blank one by accident.

## Commands

```
asckit check    # limits, image sizes, gaps. No network, no credentials
asckit ignore   # read which languages are ignored, ignore one, or stop
asckit copy-screenshots  # take the newer screenshots into the language beside them
asckit fix-names # name every screenshot the way ASCKit names them
asckit pull     # read what App Store Connect holds
asckit diff     # what a push would change
asckit push text
asckit push images
asckit experiments       # read the draft Product Page Optimization tests
asckit push-experiment-images  # upload the images of those tests
asckit library show      # the app's asset library, and what each language places
asckit library prune     # delete the library assets that nothing places
asckit price curves      # the price shapes ASCKit ships. No key, no network
asckit push products     # the names and descriptions of the in-app purchases
asckit push prices       # what each country pays for them
```

Every command takes the folder holding the Xcode project, defaulting to the
current one. ASCKit reads the app's name, its version and its languages out of
the `.xcodeproj`. A folder with none is refused. The listing itself is read from
`.asckit` inside that folder.

```
asckit check ~/Work/Stocked
```

`check` needs no key, so it works in a git hook. It exits non-zero on an error,
and `--strict` makes warnings count too.

Both push commands print the change plan and ask before writing. `--yes` skips
the question for a plan you have already read. The plan is worked out from a
listing read at that moment, so what goes up is measured against App Store
Connect as it is rather than as it was. The app does the same thing: it reads
again immediately before it writes, and if the plan moved while the sheet was
open it writes nothing and shows the new one.

`pull --write` turns a listing into app information files, which is how to start a project
from an app that already has one. It never overwrites without `--force`.

### A version App Store Connect has and this project does not

App Store Connect opens a new version on its own. Somebody adds one in the web
page, or a release goes out and the next version opens behind it.

Every command that reaches App Store Connect works on the version it read back,
and loads the folder of that name. So a version with no folder stops `diff` and
both `push` commands. `pull` says which version App Store Connect is on and
whether there is a folder for it.

The app asks the same question every time a window opens, rather than waiting
for somebody to press something. A project with no key in the key folder reads
nothing and says nothing about it, because the settings page already asks for
one.

`pull --create-version` makes the folder. It makes it empty. Nothing is copied
from the version before and nothing is brought down from App Store Connect,
because a file that arrives by itself already saying `approved` is a file that
gets published without anyone reading it. In the app the same thing is a banner
on the overview page with a button on it.

### Languages App Store Connect has and this project does not

An app usually ships in more languages than a project starts with. A new project
is scaffolded with one language, and an app that has been on the store for a
year has eleven. Until the other ten are in files, nothing here can show them or
push them.

`pull` prints every language App Store Connect holds. `pull --adopt-locales`
takes the ones this project does not list into it: the locale list gets them,
each one gets an app information file written from what the store holds, and
each one gets the folders its screenshots go in. It writes over nothing. A
language already listed keeps its place, and a file already there is left as it
is, because what is on disk may be a translation somebody is still working on.

In the app the same thing is a banner on the overview page, with a button on
it. Both go through `LocaleAdoption` in the package, so the window and the
command line refuse the same states, say the same words about why, and write
the same files.

### Languages ASCKit leaves alone

An app is often built in more languages than its store page is written in. The
Xcode project ships Romanian, and nobody is going to write a Romanian store
page. Left alone, that language is a warning on every run: `check` reads the
Xcode project's `knownRegions`, sees a language the listing has none of, and
asks for one.

Ignoring it is the answer:

```
asckit ignore ro          # ignore it
asckit ignore             # read what is ignored
asckit ignore --stop ro    # write it again
```

In the app the same thing is a menu item on the language in the sidebar, called
"Ignore This Language", and a button on that language's page. Both go through
`IgnoredLocales` in the package, so a language ignored in the terminal is
ignored in the window.

An ignored language stays in `locales` and is named in `ignoredLocales`. It
stays in the list because that is what tells `check` the app is built in it, so
the warning stops. Being named in `ignoredLocales` takes it out of everything
else: no app information file is asked for or written, no screenshots are
checked, no in-app purchase needs words in it, and no push reaches it. The
sidebar shows it under every other language, marked Ignored, so the decision is
visible and one click takes it back.

The source language cannot be ignored. Every other language is translated from
it, and a listing with no source language has nothing to say.

### ASCKit never makes a language on App Store Connect

A store page is what people read, and one that turns up because a file was on
disk is a page nobody decided to publish. So a push only writes into a
localization App Store Connect already holds.

A language in `locales` that the store has no page for is named in the plan and
left alone. Make the language in App Store Connect, run `pull` again, and the
push writes it. Or ignore it, and nothing asks about it again.

### Screenshots a language does not have its own of

App Store Connect shows the primary language's screenshots to anybody whose
language has none of its own. It does that one display type at a time, so a
language can have its own iPhone screenshots, where the words in the picture
matter, and show the English iPad ones.

For a language that reads the same words as the source, such as `en-GB` beside
`en-US`, an empty folder is either a gap or a decision, and only somebody who
knows the app can say which. Until they do, ASCKit reports it as an error,
because the usual reason for an empty folder is a half-finished export.

Saying it is a decision turns that error off:

```json
"usesSourceScreenshots": { "en-GB": ["ipad-13"], "en-AU": ["iphone-6.9", "ipad-13"] }
```

In the app the same thing is a checkbox in each device class heading on a
language's Screenshots page, called "Show the en-US ones". It is not offered on
the source language, which has nothing to fall back to.

For a language that reads different words there is no checkbox. A German
listing showing English pictures is a gap whatever anybody decides, so ASCKit
warns rather than blocking the push, and it warns again when the images in the
folder are the English files byte for byte. Somebody who means it can silence
the warning.

This lives in `asckit.json` rather than in a version folder, so it holds for
every version, including the ones not made yet. The push is what it always was:
it uploads what is in the folder, and a folder with nothing in it leaves the
language with no screenshots of its own, which is what makes App Store Connect
show the source language's.

A language named here that does have screenshots is a warning. The push uploads
what is on disk, so the files win and the setting says nothing.

### The asset library

App Store Connect keeps every image and video of an app in one asset library.
A screenshot on a version is a placement: one asset, put in one set of one
language. ASCKit writes screenshots, previews, and the header and search
results art this way.

A push uploads each file once, whatever number of languages, sets and
treatments use it. Then it places the asset in each set and sets the order.
Placements that already match stay as they are.

The library gives no checksum for an asset. So ASCKit keeps its own record in
`.asckit/asset-library.json`. The record maps the MD5 and size of each file to
the asset it became. Commit it with the project. An asset with no record entry
reads as a different image from every file here, so a push replaces its
placement. That includes an asset uploaded through the web page, or by a clone
that did not commit the record.

App Store Connect moved the screenshots that the old endpoints uploaded into
the library. The first read pairs each old screenshot with its placement, so
nothing goes up again.

A screenshot taken off a set stays in the library. A push loses nothing, so it
asks nothing extra. `asckit library prune` deletes the assets that nothing
places, and only those in Prepare for Submission. Without `--yes` it lists them
and deletes nothing.

App previews sit beside the screenshots, with the same device classes:

```
versions/1.0/previews/en-US/iphone-6.9/01-onboarding-iPhone-6.9-en_US.mov
versions/1.0/previews/en-US/iphone-6.9/poster-frames.json
```

`poster-frames.json` is optional. It maps a file name to the frame App Store
Connect shows before the video plays, as `HH:MM:SS:FF`. A set takes three
previews at most.

The header and the search results art are one file each for a language:

```
versions/1.0/creative/en-US/header.png
versions/1.0/creative/en-US/search-results.png
```

Each one can be a `.png`, a `.jpg` or a movie. A language with a header and no
`search-results` file shows the header in search results too. That header has to
be a universal image, a 5244x2950 `.png`, or the check stops the push. The store
shows this art only on iOS and iPadOS 27 and later.

A Product Page Optimization treatment takes the same `previews` and `creative`
folders.

### What App Store Connect holds for an empty set

A set with no files here is the one a person cannot see. The folder is empty,
and the pictures a push takes off the set are only in the web page.

So the window shows them. Under the empty box on a language's Screenshots page,
each device class with nothing in it shows the pictures the store holds, with
the file name under each one. That name is what to look for on the disk the
export went to.

The pictures are read from App Store Connect and never written here. The store
serves a new encoding of the image somebody uploaded, with other bytes, and a
file written from it would make the next push read a changed image and upload
it again. What is shown is the last listing the window read,
so it is a version's worth of pictures, and the line above them says which
version.

### The language beside this one got the newer screenshots

`es-ES` and `es-MX` read the same pictures. A new export usually lands in one of
them, and the other keeps last month's. The check says the older one has drifted
from the source language, and it is right, but the answer is not in the source
language. It is next door.

```
asckit copy-screenshots              # read what could be copied, numbered
asckit copy-screenshots --accept 1   # make one copy, by its number in that list
asckit copy-screenshots --all        # make every copy in the list
```

Which language is newer is the date on the files. A copy is offered only where
the two sets really differ, so a folder somebody checked out again is left
alone.

Only inside one language. The `en-US` screenshots are English pictures, and
copying them into `es-ES` would publish a Spanish listing with English artwork.
App Store Connect already shows them wherever a language has none, and saying
that on purpose is what `usesSourceScreenshots` is for. `zh-Hans` and `zh-Hant`
count as different languages here, because a different script is a different
picture.

A copy makes the two folders match. Whatever the older language held goes to the
Trash, so nothing is left half old and half new.

In the app the same thing is a line under the device class heading on a
language's Screenshots page, with a "Copy from es-MX" button on it.

### Product Page Optimization

A Product Page Optimization test shows other pictures to some of the people who
find the app. Each test has treatments, and each treatment has a page for each
language, with screenshot sets like the App Store page.

ASCKit never makes a test, a treatment or a language of a treatment. They are
made in App Store Connect. ASCKit reads the tests that are still drafts
(Prepare for Submission) and fills their screenshot sets. A test that went to
review takes no images, so ASCKit does not read it.

```
.asckit/product-page-optimization/
└── Bigger buttons/              the test, named as App Store Connect names it
    └── Treatment A/
        └── en-US/
            └── iphone-6.9/
                └── 01-running-low-iPhone-6.9-en_US.png
```

The folder is beside `versions`, because a test belongs to the app and can run
across two releases. Reading App Store Connect makes the empty folders for every
language of every draft treatment. In the terminal that is `asckit experiments`,
and the project window does it when the Product Page Optimization page opens.

The images are named and checked like every other screenshot. The same limits
apply: ten per set, the sizes of the device class, and no alpha channel.

The inbox takes them too. The folders say which treatment, and the file name
says the language and the device class, in the same format as the App Store page:

```
inbox/product-page-optimization/Bigger buttons/Treatment A/03-shopping-iPhone-6.9-en_US.png
```

`asckit inbox --file` and the inbox sheet file them into the treatment. A push
uploads each new file once and places it, as for a version.

```
asckit experiments               # read the draft tests, make the folders, say what a push would do
asckit push-experiment-images    # upload them
```

### Warnings somebody has read

An error blocks publishing. A warning does not, and some of them are answered
once and then true for the rest of a release: this version really is the app's
first, so it has no whatsNew.

Silence one, and a check hides it:

```
asckit silence              # read what is silenced, numbered
asckit silence --all        # silence every warning this version has now
asckit silence --show 2     # bring one back, by its number in that list
asckit silence --clear      # bring them all back
```

In the app the same thing is a button on each warning, "Silence All" over the
warning list, and a Silenced group under it with a button on each row and one
over the group.

A silence goes in `silenced.json` beside the version. A silence for a warning
about an in-app purchase or its price goes in `products/silenced.json` instead.
Each silence keeps the rule that made the warning. It also keeps what the
warning is about, such as a language, a field or a file. So a warning from the
same rule about another language still shows, because nobody silenced it. A
silenced warning stays hidden when its message changes, for example when it has
a new count. The rule stays the same when somebody edits or translates the
message.

A silence beside version 1.0 hides its warning only in 1.0. In 1.1 that warning
shows again. A silence in `products/silenced.json` hides its warning in every
version. `asckit silence` numbers the silences beside the version first, then
the ones in `products/silenced.json`. A silence left behind by a warning
somebody fixed stays in the file. Both front ends say which ones those are.
When `silenced.json` is missing or cannot be read, a check writes an empty one.

Errors are never silenced. An error is what App Store Connect refuses, and
hiding one would only move the refusal later. A silenced warning is counted out
loud in the summary, so "nothing wrong" never hides a decision.

## How App Store Connect behaves

Each of these is in the code with a comment saying the same thing. None of them can be worked out from Apple's
documentation. Each one is a run that fails, or one that appears to succeed and
does nothing.

**Locale codes are not consistent, and App Store Connect ignores one it does
not know rather than refusing it.**
Italian is `it` and Japanese is `ja`, with no region. Dutch is `nl-NL` and German
is `de-DE`, with one. A code App Store Connect does not know is ignored rather
than refused, so a run looks successful and uploads nothing. `asckit pull`
prints the codes the API actually returns, which is the only authoritative list.

**The keyword field is 100 characters, and a character is a character.** A
Japanese or Chinese keyword string gets the same 100 as an English one. The
belief that Apple counts this field in UTF-8 bytes is common and wrong. ASCKit
counted it that way until it blocked a Japanese field the store accepts.

**Apple never added a display type for the 6.9 inch iPhone or the 13 inch iPad.**
They widened what the old identifiers accept. A 1320x2868 image goes up under
`APP_IPHONE_67` and a 2064x2752 one under `APP_IPAD_PRO_3GEN_129`. That mapping
is confirmed by working tooling, not by Apple's documentation.

**Name and subtitle are written to a different resource from the rest.** They
are on `appInfoLocalizations`, with the privacy policy URL. The support URL is on
`appStoreVersionLocalizations`, with the description and the keywords. Writing either to the wrong
resource is a 409, not a bad value.

**An app has more than one `appInfo`**, one live and one editable. Writing the
name to the live one is a 409. The editable one is the one whose state is
`PREPARE_FOR_SUBMISSION`.

**Uploading an asset takes four steps.** Reserve it in the library. Send each
part to the address Apple names. Commit it with `uploaded: true`, which takes no
checksum. Then poll until the state is `PREPARE_FOR_SUBMISSION` or `FAILED`.
The upload address is unauthenticated, so the bearer token must not go with it.

**A placement never changes.** To put another asset in its place, delete it and
make a new one. One ordering request then sets the order of a whole set.

**A price point belongs to one product in one country.** The identifier encodes
all three, so a point read for one subscription is not valid on another, and a
one-time purchase's point is not valid on a subscription at all. There is no
global ladder to cache.

**An in-app purchase's price points come from `/v2` and their equalizations from
`/v1`.** There is no `/v2` equalizations endpoint. The version is different for
each and following the wrong one is a 404.

**A product's words belong to a version, not to the product.** API 4.4.1
deprecated every endpoint that hung a localization off an in-app purchase, a
subscription or a subscription group, the reads as well as the writes. They are
listed from `/v1/inAppPurchaseVersions/{id}/localizations` and written at
`/v2/inAppPurchaseLocalizations`, with a `version` relationship rather than the
old `inAppPurchaseV2` one. The version list itself is `/v2` for a purchase and
`/v1` for a subscription and a group, which is Apple's split rather than a typo.

**ASCKit never makes a version and never moves one's state.** A version is what
puts a product in front of App Review, so a person makes it in App Store
Connect. A push writes into a version in `PREPARE_FOR_SUBMISSION` and refuses a
product that has none, in the plan rather than as a failure afterwards. `asckit
pull --products` prints each product's version so that is visible first. The
cost is real: a product whose words have never been drafted needs one click in
App Store Connect before ASCKit can write to it.

**Only `PREPARE_FOR_SUBMISSION` takes a change.** Every other state is a version
App Review has already seen. A read still shows those words, so a pull and the
app window show what the store sells under today, and only a push needs a draft.

**A subscription price says `preserveCurrentPrice` going out and `preserved`
coming back.** Same fact, two names. Reading it under the name you wrote gets
nil every time rather than an error, so the flag that decides whether existing
subscribers keep their price reads as unset.

**A subscription has no price schedule, and still takes every country in one
request.** `POST /v1/subscriptionPrices` writes one country, which is the
obvious route and the wrong one for 175 of them. `PATCH /v1/subscriptions/{id}`
takes a compound document instead: the prices travel in the request's
`included` array under local ids such as `${price-USA}`, and the `prices`
relationship points at those ids. That is the same shape a one-time purchase's
`POST /v1/inAppPurchasePriceSchedules` uses, and Apple documents the schema for
it but publishes no worked example and no cap on how many it will hold.

**Whether either one replaces the whole price set or adds to it is not
documented.** ASCKit sends every country in both, which is right either way.
Sending only what changed would empty every other country if it replaces.

**A yearly subscription has two prices in every country.** Apple returns an
`UPFRONT` row holding what it costs bought outright and a `MONTHLY` row holding
one instalment. Keeping whichever arrives last reports a 14.99 subscription as
costing 1.49. Two rows per country also means 175 countries is 350 rows, which
is past the 200-row page, so a reader that does not follow `links.next` loses
half of them without saying so.

**The refusal for a bad instalment names the wrong price.** Writing a yearly
price on its own is answered with
`ENTITY_ERROR.RELATIONSHIP.INVALID_PRICE_TOO_HIGH`, saying "the selected price
point exceeds the allowed commitment price threshold for subscriptions with
monthly plan". The wording points at the price you sent. The price that is too
high is the monthly one you left alone. So cutting a yearly price means cutting
its instalment in the same request.

The rule behind it is documented, once there is a name to look it up under.
Twelve instalments must total at least the upfront price and no more than 1.5
times it. That leaves an instalment somewhere between a twelfth and an eighth
of the year, which is narrow enough that a coarse ladder can hold nothing in
it. A country like that has to be left out, because sending its year alone
takes the whole request down.

The lower bound is the one that surprises. An instalment can be refused for
being too cheap as well as too dear, because undercutting the year with the
monthly plan is not allowed either.

**A price cut and a price rise land in different places, and only the rise is
easy to find.** A cut takes effect at once and replaces the row it changes. A
rise becomes a scheduled price change dated the day you sent it, sitting beside
the old row, which stays and is marked `preserved` for people who already
subscribe. So a push that lowers 299 countries and raises 2 shows 2 on App
Store Connect's scheduled price change page, and the other 299 are already live
in the subscription's own price list. Both worked. The page only ever holds
rises.

`preserveCurrentPrice` is what asks for that, and it does nothing on a cut.
Everybody gets a lower price, whatever you send.

**A price point comes back with no country on it unless you ask.** Filtering by
territory does not imply including it, and a point with no territory
relationship is unusable, so the whole ladder reads as empty.

**Equalizations answer with every country except the one you asked about.** The
base country is not in the reply, and its own equivalent price is the price you
asked with.

**`baseTerritory` is required on a price schedule**, and Apple's own examples
leave it out.

**An image is its bytes.** The file name sets the upload order and App Store
Connect keeps it, but nobody sees it. So renaming a file needs no upload, and
putting the same images under new numbers is one call.

**A placement can change only while its version is editable.** An approved
version refuses a new one. Deleting a placement leaves its asset in the
library, so a push loses no image.

## Working on ASCKitEngine

```
swift test
```

The engine is testable with no network and no window. That is the reason for the
layering. Every request goes through a `Transport` protocol, so tests run against
recorded responses and never reach Apple. `ASCKitTestSupport` holds the one fake
App Store Connect every test target uses. Nothing that ships may link it.

**SwiftLint** runs as a build tool plugin on every target. Rules are in
`.swiftlint.yml`. **SwiftFormat** settings are in `.swiftformat`. Run it in
`--lint` mode before you send a change.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright 2026 Alecs Popa.

The source is available under the [PolyForm Noncommercial License
1.0.0](LICENSE). In short:

- You can read, build, run and change the code for any noncommercial purpose.
  Personal use, research, and use by charities, schools and public bodies are
  noncommercial.
- You cannot use the code for a commercial purpose. That includes a paid
  product or service, and work for a company.
- If you share the code, you must include the license and the notice line.

The license text in [LICENSE](LICENSE) is the binding text. This summary is not.
For a commercial license, open an issue.
