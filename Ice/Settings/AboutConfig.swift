//
//  AboutConfig.swift
//  Ice
//

import DragonKit
import Foundation

/// Ice 2's content for DragonKit's shared About pane.
///
/// The kit owns every row title, SF Symbol, ordering and detail string — ``AboutContent``
/// assembles them and ``AboutPane`` renders them. Ice 2 supplies only URLs and proper nouns.
/// This used to pass free-form `links`/`credits` arrays; five apps used them to ship five
/// visibly different panes, so DragonKit 3.0.0 replaced them with fixed slots.
///
/// The version is single-sourced from the bundle via ``DragonAbout/versionString(bundle:)`` —
/// never hardcoded.
enum AboutConfig {
    /// The canonical marketing page. The kit's `websiteMatchesSupportRepo` checks this path
    /// against the support URL's repo name, so it must be `/ice-2/`, not the bare hub.
    private static let websiteURL = URL(string: "https://www.dragonapp.com/ice-2/")!

    /// Support goes straight to the GitHub issues page.
    private static let issuesURL = URL(string: "https://github.com/teddychan/ice-2/issues")!

    static var content: AboutContent {
        AboutContent(
            appName: Constants.displayName,
            versionString: DragonAbout.versionString(),
            // Assembled by the kit so the format matches every other Dragon app. Ice 2 was the
            // app that spelled out "Copyright ©" where the others used the symbol alone.
            //
            // One holder, not two. This row used to read `© 2025 Jordan Baird · © 2026 Teddy
            // Chan`; only Ice 2 and clipmenu-2 did that, and DragonKit 4.0.0 made the
            // single-holder form canon (CONFORMANCE §R14) after five About panes were put side by
            // side. The row names who maintains and distributes *this* app. Ice 2's lineage is
            // not dropped by saying so — it is carried by the `Original project` link and the
            // `Based on` credit below, both driven by `OriginalWork`.
            //
            // `NSHumanReadableCopyright` now matches this string exactly. It carried both holders
            // until 2.14.7, on the reasoning that Ice 2 is a git fork of Jordan Baird's Ice rather
            // than a clean reimplementation, that GPL-3.0 §4 requires his notice to travel with the
            // binary, and that the plist key IS the binary's notice.
            //
            // The first two clauses are true and unchanged. The third was the mistake: that key is
            // an OPTIONAL Apple key, named by no licence, and three of the five Dragon apps shipped
            // without it at all. §4's "conspicuously and appropriately publish an appropriate
            // copyright notice" is carried by `LICENSE`, which fills in the GPL's own template with
            // his name and year, and by `Resources/Acknowledgements.rtf`, which states in as many
            // words that Ice 2 inherits GPL-3.0 from the original Ice. Neither moves here. What the
            // plist key does is display a line in Finder's Get Info panel, which makes it
            // presentation — the same thing this row is — so the two disagreeing was drift, not
            // compliance.
            //
            // Both are now the app's own holder, and the lineage sits where the pane puts it:
            // ``OriginalWork`` drives the `Original project` link and the `Based on` credit, and
            // the licence texts are bundled and published at dragonapp.com/ice-2/licenses/.
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            websiteURL: websiteURL,
            supportURL: issuesURL,
            // Third-party notices: the verbatim MIT text for the six packages below. Trailing
            // slash: it is the path Pages serves, so the row does not point at a redirect. This
            // replaces the row that opened `Resources/Acknowledgements.pdf` before DragonKit
            // 3.0.0 removed `acknowledgementsURL` — the slot stayed empty rather than take a
            // `file://` URL, because the kit derives a row's link text from its URL and would
            // have rendered the PDF's absolute filesystem path.
            //
            // The bundle still carries the same notices as a document, generated alongside this
            // list by `scripts/generate-acknowledgements.swift`. The kit's own doc comment calls
            // hosting them on the site *instead* a weaker reading of MIT's "included in all
            // copies"; shipping both settles that, and this row stays because a web page is the
            // more readable copy.
            licensesURL: URL(string: "https://www.dragonapp.com/ice-2/licenses/")!,
            // Ice 2's own licence, which is not the row above: `licensesURL` is the third-party
            // notices page, this is the `License` credit. Adjacent since DragonKit 4.0.0 made
            // `licensesURL` required and put it here; the kit's own comment says not to merge them.
            license: "GPL-3.0",
            // Drives two rows from one value: the `Original project` link and the `Based on`
            // credit. The link row was missing entirely before DragonKit 4.0.0 — Credits said
            // "Based on Ice by Jordan Baird" while nothing in the pane linked to Ice, so a reader
            // was told there was an upstream and given no way to reach it. That was possible
            // because the upstream name and its URL were two unrelated optionals; 4.0.0 folded
            // the URL into `OriginalWork`, which is why they can no longer disagree.
            originalWork: OriginalWork(
                name: "Ice",
                author: "Jordan Baird",
                url: URL(string: "https://github.com/jordanbaird/Ice")!
            ),
            attributions: [
                // Every THIRD-PARTY package Ice 2 links, as `name → licence`, and the one list a
                // reader sees without leaving the app. `AcknowledgementsTests` pins it to
                // `Package.resolved` and to the bundled notices: hand-maintained copies of this
                // list drift, which is how the notices came to name LaunchAtLogin years after it
                // was dropped.
                //
                // DragonKit is deliberately NOT here, though it is a resolved package and does
                // appear in both notice documents. The kit's `Attribution` is documented as "a
                // third-party thing an app bundles", and DragonKit is not third party — it is
                // Dragon App's own shared library, which is why `AboutContent.creditRows` emits
                // an unconditional `Built with → DragonKit vX.Y.Z` row for every app. Listing it
                // here as well printed it twice in Credits and made Ice 2 the only one of the
                // five apps that did: the sample app links DragonKit and DragonKitUpdates and
                // still attributes Sparkle alone, and clipmenu-2, spectacle-2 and
                // yahoo-keykey-2 all match it.
                //
                // The notice documents keep DragonKit, and must: MIT requires the notice to
                // travel with copies, and the Built-with row carries a version, not a licence.
                Attribution(name: "Sparkle", license: "MIT"),
            ]
        )
    }
}
