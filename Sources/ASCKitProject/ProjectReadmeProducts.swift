import Foundation

/// The part of a project's README that is about in-app purchases.
///
/// Its own file because the README outgrew one, and this is the half that
/// is about money rather than about words.
enum ProjectReadmeProducts {
    static let text = """
    ## An in-app purchase

    One file per purchase, in `products/`, named after the product id your app
    asks the store for.

    These sit beside `asckit.json` rather than inside a version, because a
    purchase is not tied to one. It hangs off the app, and a price change takes
    effect on the date the price says, with no release involved.

    ```json
    {
      "productId": "com.example.pro.monthly",
      "kind": "auto_renewable_subscription",
      "subscriptionGroup": "Pro",
      "subscriptionPeriod": "ONE_MONTH",
      "status": "needs_human",
      "reviewNote": "Sign in with the demo account to reach the paywall.",
      "price": {
        "baseTerritory": "USA",
        "baseAmount": "4.99",
        "curve": "purchasing-power",
        "preserveCurrentPrice": true,
        "overrides": {
          "JPN": { "amount": "800", "why": "600 reads as a converted price." },
          "RUS": { "skip": true, "why": "Not sold here." }
        }
      },
      "localizations": {
        "en-US": { "name": "Pro Monthly", "description": "Everything in Pro, monthly." },
        "de-DE": { "name": "Pro Monatlich", "description": "Alles in Pro, monatlich." }
      }
    }
    ```

    `kind` is `consumable`, `non_consumable`, `non_renewing_subscription` or
    `auto_renewable_subscription`. Only the last one belongs to a group.

    `status` works the way a language file's does. Only `ai_approved` and
    `approved` are ever published, and only a person sets `approved`.

    The name is 30 characters and the description is 45. Both are needed in
    every language: App Store Connect will not take a purchase without them, so
    a missing one is not "leave it alone" the way a listing field is.

    ### A subscription group

    One file per group, in `products/groups/`, named after the group's reference
    name. That is the name each subscription gives in `subscriptionGroup`.

    ```json
    {
      "status": "needs_human",
      "localizations": {
        "en-US": { "name": "Pro", "customAppName": "My App" },
        "de-DE": { "name": "Pro" }
      }
    }
    ```

    App Store Connect does not take a subscription for review until its group
    has a display name in at least one language. `name` is 64 characters.
    `customAppName` is 30 characters and optional: leave it out and the store
    shows the app's own name.

    ASCKit never makes a group. It writes the words of a group that App Store
    Connect already has.

    An amount is written as a string. `4.99` as a JSON number is a `Double` and
    does not come back out of the file as the price you wrote.

    ### Price curves

    A curve says what to charge in each country, as a fraction of the base
    price. Apple will tell you, for the price you picked at home, what it
    considers the equivalent price in every other country, already in local
    currency, and a curve works from that.

    ```
    apple-equalized        Apple's price everywhere. The default
    tier-anchored          the base price in richer countries, 60 percent elsewhere
    purchasing-power       four steps by income, down to a third
    emerging-market-push   the same steps cut much harder, down to a fifth
    proceeds-parity        raises the price where tax is high, so your payout matches
    ```

    Apple's equivalent price is not a plain conversion. It converts at Apple's
    own rate and then works the local sales tax in, and the two together put a
    euro country about 40 percent above the base price converted at a market
    rate. So the three income curves take that step back out first, and price
    from the base converted. `apple-equalized` does not, because Apple's price
    is what it means, and neither does `proceeds-parity`.

    That conversion was measured once, against real prices on a stated day, and
    it is written down with its date. It goes out of date as currencies move,
    and `asckit check` says so once it is over a year old. It is the one place
    in ASCKit that holds an exchange rate.

    A few countries have a ratio above one, where Apple charges less than a
    straight conversion. Qatar, Indonesia, Pakistan and Canada are the notable
    ones, and these curves raise their price rather than lowering it.

    `asckit price curves` prints them with what each one is for. A company name
    such as `netflix` finds the curve with that shape, and the file keeps the
    shape name, because a company's prices change and a shape does not.

    ### Rounding, and why your price goes up

    **You cannot charge any amount you like, and ASCKit rounds up.**

    The App Store offers a fixed ladder of prices in each country, and its steps
    end in .49 or .99. ASCKit works out what the curve asks for, then takes the
    next step up, then one more step to reach a .99 where there is one. So a
    curve asking for 3.20 charges 3.99, not 3.49.

    Up rather than to the nearest step, because rounding down charges less than
    the curve asked for and the money lost is real. Onto a .99 because that is
    the ending to land on, and a .49 causes trouble at some prices.

    One step past a .49 and no further, so rounding never skips a whole tier
    looking for an ending it likes. A currency with no minor unit, such as the
    yen, has no .99 anywhere on its ladder, so it simply takes the next step up.

    An amount that is already a step is taken as it is, whatever it ends in. If
    you write 3.49 and the store offers 3.49, that is what you get.

    Every country where rounding moved the number says "rounded up" in the
    change plan, and the plan repeats this rule above the prices every time.

    ### Seeing what would change

    `asckit diff` compares the files against the store. It shows the words for
    every purchase, and it says nothing about prices unless you ask, because
    reading a price means reading every price the store will sell that product
    at.

    ```
    asckit diff --prices
    ```

    That reads the prices and prints every country. Without it the plan shows
    the twelve biggest moves and says how many are left.

    The plan says which of the two rules applies to each purchase, in words,
    every time. It also says whether people who already subscribe keep what
    they pay.

    ### Writing it

    ```
    asckit push products    the names and descriptions
    asckit push prices      what each country pays
    ```

    Two commands, not one. A wrong description is an edit. A wrong price is
    money.

    `asckit push prices --dry-run` builds every request, sends none of them, and
    prints the exact body App Store Connect would get. It is the same body a
    real run sends, because the same code makes both. Run it once before you
    trust the real thing.

    A plan where any country would pay more needs `--yes-raise-prices` as well
    as `--yes`. One word is not enough for a rise.

    ### When it fails

    Both kinds go in one request, so a run either wrote everything or wrote
    nothing.

    Nothing is the likely case, but do not take it as given. Apple does not say
    that a rejected request of this shape is applied all or nothing, and a
    refusal is not the same as a promise. Read it back with `asckit diff
    --prices`, or just run the push again: it reads first and writes only what
    is still wrong, so it is safe whichever way the failed run landed.

    There is no automatic retry. A price that has already started cannot be
    deleted, and a loop is the wrong thing to point at that.

    On `--one-country-at-a-time`, one country failing does not stop the rest,
    and the countries that failed are named so you can see which they were.

    Every push writes a receipt into `history/`. A price receipt records what
    each country paid before and after, the price point that was written, and
    whether people who already subscribe were protected. Apple regenerates price
    point identifiers, so the one that actually went is worth keeping.

    ### Setting one country by hand

    An override names an amount, or an exact price point, or `skip`. Write a
    `why` beside it. A price nobody can explain a year later is the one that
    goes wrong, and ASCKit warns when a reason is missing.

    ### Two rules that are opposite

    **A one-time purchase has one price schedule, and writing it replaces the
    whole thing.** A country left out does not keep its price. It goes back to
    Apple's equivalent of the base price. So ASCKit always writes every country
    for a one-time purchase.

    **A subscription has no schedule at all**, but it takes an update that
    carries every country in one request. Apple does not say whether that
    replaces the price set or adds to it, so ASCKit sends every country either
    way, which is right whichever it turns out to be.

    Both kinds therefore go in one request, and nothing is ever half applied.
    `--one-country-at-a-time` writes a subscription's countries separately
    instead, which is slower and is how you find out which country App Store
    Connect objected to when the one request comes back refused without saying.

    The change plan says which rule applies to each purchase, every time.

    ### People who already subscribe

    `preserveCurrentPrice` is true unless you say otherwise, so a price change
    reaches new customers only. False on a rise puts every existing subscriber
    into Apple's consent flow: they are emailed, they have to agree, and the
    ones who do not answer are cancelled at renewal.
    """
}
