# Groundwork

A native iPhone coffee journal with offline journaling and optional on-device or OpenAI photo recipes. SwiftUI, iOS 17+, direct system SQLite3, no third-party dependencies. On-device AI needs Apple Intelligence; optional OpenAI processing uses your own paid API account. Starts empty.

## Open and run

Open `Groundwork.xcodeproj` in full Xcode (26 or newer, with an iOS SDK; required for the Liquid Glass app icon). Select the Groundwork scheme, then an iPhone simulator, and Run. For a physical phone, connect it, enable Developer Mode, choose your own signing team under Signing & Capabilities, and keep the existing bundle identifier `com.dailygrounds.journal` to preserve the installed app identity, or change it to a unique identifier if you are creating a separate app. A free Apple development account supports personal device testing subject to Apple's provisioning limits. Signing uses the development team configured in Xcode; no signing credentials are stored in the repository.

## Run in the simulator

```sh
./scripts/run-simulator.sh --device <UDID>
```

Boots the selected simulator, builds the current source, installs and launches Groundwork, and opens Device Hub (Xcode 27). Use `--device <UDID>` or `SIMULATOR_UDID` to select a simulator; list them with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available`. Use `--no-open` to run without opening the display. Older Xcode installations fall back to Simulator when the Device Hub URL is unavailable. Set `DEVELOPER_DIR` to select another Xcode installation. Build logs are written to `output/simulator-build.log`.

## Update a physical iPhone

Run from Terminal (from any working directory when using the script's full path):

```sh
./scripts/update-device.sh --device <UDID>
```

This builds and signs the current local source, installs it over the existing app, and launches Groundwork. It works over USB or a reachable Wi-Fi connection. Keep the iPhone unlocked with Developer Mode enabled and the development profile trusted. Xcode must have your signing account configured; macOS may ask you to authorize code signing. The script does not uninstall the app or fetch source updates.

Use `--device <UDID>` (or `DEVICE_UDID`) to select a paired phone, and `--no-launch` to install without opening the app. Find identifiers with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl list devices`. Set `DEVELOPER_DIR` for another Xcode installation. Build logs are written to `output/device-build.log`.

## Use

The three tabs are Coffees, History and Settings. Add a coffee from the empty shelf or toolbar; camera/photo scanning is offered before manual entry. Finished bags can be archived from the coffee's actions menu without losing history. Search the shelf by coffee, roaster or origin. Roast age appears when the roast date is known.

A coffee's detail page shows a compact identity header, a prominent Brew action, last/best-rated recipes, saved recipes and recent cups before optional suggestions. New cups start from the last recipe for the coffee and method, or method-specific defaults. The grinder picker still offers only Blackdrop and Kingrinder.

Coffee dose uses a **10–25 g slider in 0.1 g steps**. Grind setting uses a **20–180 slider in whole steps**. Editing normalizes these values to the supported ranges. Espresso retains the fixed-time machine workflow without measured yield or custom time. AeroPress water uses a **50–500 g slider in whole-gram steps**. Total brew time uses a **0–10 minute slider in five-second steps**, displayed as minutes and seconds; zero leaves the time unrecorded. Every slider also has minus/plus tap controls for precise adjustments. There is no brew-date input: the record is timestamped when Save is tapped, including when editing an existing brew. Method switching keeps a separate in-session draft for each method.

Recipe and Taste are separate editor stages, operated with swipes and taps. Save now and rate later, or add an overall taste score, descriptive espresso flow, toggleable sensory notes, and optional color/texture preference ratings. The brew form has no text editors; existing recipe instructions and legacy tasting notes remain readable. Validation stays inside the editor and retains the draft. Canceling changed forms asks before discarding them.

Recipe instructions persist when brewing again. Tasting notes and all ratings are specific to each cup and clear on repeat; previous feedback is shown as reference. History shows recipe parameters, taste, date and changes from the prior comparable cup. Tap a row for read-only details, then choose Edit, Brew again or Save as a recipe. Compare accepts two cups of the same coffee and method. Swipe deletion offers Undo until dismissed or superseded by another deletion.

## Appearance

The app uses the custom **Terracotta & Cocoa** palette: warm porcelain and clay in light mode, roasted cocoa and soft terracotta in dark mode. **Settings → Appearance → Theme** offers System (the default), Light, and Dark; the choice persists on this device and applies to editor and recipe sheets as well as the main tabs. Shared colors in `App/JournalTheme.swift` cover screen and card surfaces, navigation titles, primary/secondary text, terracotta actions, errors, photo placeholders, and brew ratings. Selected ratings use the terracotta accent in both modes, with muted cocoa for unselected stars. Primary and secondary text on both surfaces, and action/error text on cards, have at least 4.5:1 contrast.

The app icon is a native layered Icon Composer resource in `App/AppIcon.icon`, with light and dark Terracotta & Cocoa variants, a clay glass cup, warm taupe steam, and cocoa coffee beans. iOS 26+ renders its Liquid Glass highlights and supports the system’s clear/tinted treatments. Xcode generates static fallback icons for earlier supported releases. The Home Screen icon follows the **Home Screen → Edit → Customize** appearance setting: choose **Auto** to follow the device’s light/dark appearance. This setting is independent of **Settings → Appearance → Theme** inside Groundwork. See [Apple’s Home Screen guide](https://support.apple.com/guide/iphone/customize-apps-and-widgets-on-the-home-screen-iph385473442/26/ios/26) and [Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

## Storage and architecture

- `Sources/GroundsCore`: typed Codable models, validation, repeat mapping, SQLite repository and versioned backup.
- `Sources/CSQLite`: small module map over the platform SQLite header/library.
- `App/GroundworkApp.swift`: shelf, coffee detail, settings, backup and main-actor store.
- `App/CoffeeEditor.swift`: camera/photo import, label extraction and coffee editing.
- `App/BrewViews.swift`: dose/grind sliders, brew editor, history, details and comparison.
- `App/RecipeView.swift`: evidence-based suggestions, structured photo recipes and editable recipe handoff.
- `Sources/GroundsCore/BrewAdvice.swift`: recorded-evidence suggestions and validated starting recipe plans.
- `App/JournalTheme.swift`: adaptive Terracotta & Cocoa palette and shared navigation, form, list, and action styles.
- `Tests/GroundsCoreTests`: XCTest persistence and backup checks.
- `Verification`: dependency-free executable fallback running equivalent checks when XCTest is unavailable.

App sandbox: `Library/Application Support/Groundwork/journal.sqlite` (the app moves an existing `DailyGrounds` data folder on first launch after upgrading). SQLite WAL/SHM files, and `Photos/<UUID>` files. PhotosPicker imports only the chosen image; JPEG bytes are copied locally. Journaling has no network or cloud dependency; optional photo recipes contact OpenAI only when requested. The database has explicit coffee/brew columns and a saved-recipe table, foreign keys, cascade deletion and schema version 5 (additive archive, recipe-instructions and saved-recipe storage; existing journals upgrade automatically). Dates use Foundation reference-date seconds for lossless round trips. There is one UI-owned repository connection. Files from removed/replaced photos are retained, avoiding accidental loss; backups include only referenced photos. Uninstalling the app removes its sandbox.

## Local OpenAI key

In **Settings → Photo recipes and label scanning**, choose **OpenAI**, paste an API key and tap **Save key**. You can replace or remove it there. The field is masked and cleared after saving, leaving Settings, or moving the app out of the foreground. The saved key is kept in the device Keychain with `WhenUnlockedThisDeviceOnly` protection: it does not sync through iCloud Keychain or migrate to another device. It is separate from the SQLite journal and excluded from JSON exports. Keychain items may survive uninstalling the app; use **Remove key** to explicitly delete it.

Saving a key does not contact OpenAI or check whether it works.

## Photo recipes

Open a coffee with a saved label photo and choose **Starting recipe from label**. Select Espresso or AeroPress, then generate. On-device mode runs Apple Vision and Apple Intelligence locally. OpenAI mode sends the resized, re-encoded, metadata-free JPEG and coffee details directly to OpenAI using the saved key. API charges may apply. No journal history is uploaded. OpenAI requests use `gpt-4.1-mini` and `store: false`.

Results use a structured, validated recipe plan with a bounded dose, generic grind description, optional AeroPress time, steps and labeled assumptions. The app does not derive grinder clicks or observed ratings from a photo and retains the current recipe's water amount. **Use this recipe** opens an editable brew; **Save recipe** stores a reusable recipe without logging a cup. Sharing is also available. Starting recipes remain proposals: check the label and adapt to taste. Closing the sheet cancels local generation.

## Backup

Settings → Backup exports a JSON envelope with `schemaVersion: 1`, all coffees/brews, saved recipes, and base64-encoded original local photo bytes. JSON is only the portable backup format; live persistence is SQLite. Use Files to save/share the export. Treat backups as private: they are unencrypted and include notes/photos.

Import is **additive**, never a replacement. It validates the entire envelope, required fields, finite positive numeric values, IDs, relationships and photo references before saving. Identical IDs/records are idempotent; conflicting existing coffee, brew or photo IDs abort the import. If an edited record conflicts, preserve both exports and resolve that conflict outside the app; import does not silently overwrite it. All record writes run inside one SQLite transaction. Photo files are written atomically and newly written files are removed on rollback. A process/device crash between photo writes and database commit may leave unreferenced files but cannot replace existing records. No destructive restore mode is offered. Export before moving devices or uninstalling.

Backups and Photos imports are loaded into memory and processed on the main actor; very large libraries/photos may pause the UI. The format has no arbitrary file paths and only UUID photo filenames are accepted. Import limits and streaming are future improvements.

## Verification

From this directory:

```sh
swift test
swift run VerifyJournal
swiftc -frontend -parse App/GroundworkApp.swift
plutil -lint Groundwork.xcodeproj/project.pbxproj
```

`swift test` is the normal XCTest entry point. Use full Xcode for XCTest and iOS builds; if `xcode-select` points to Command Line Tools, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when running these commands. `swift run VerifyJournal` provides dependency-free repository checks when XCTest is unavailable.

Coverage: reopen persisted records, coffee-specific relationships and cascade deletion, orphan rejection, blank/numeric validation, repeat identity/date/recipe mapping, backup photo-byte round trip, repeat import, unsupported schema, missing photos, malformed relationships, and non-destructive conflict rejection.

With Xcode, also manually verify: both brew methods; edit/repeat/delete; cancel editors; Photos selection/cancellation/removal; export and import via Files; relaunch persistence; larger text and VoiceOver; an empty install; and an import conflict that leaves the existing library unchanged.

## Suggestions from brew scores

Choose **Find a recipe from my ratings** on a coffee. It opens on a method with rated history and uses up to 30 recent rated brews for that coffee and method. The highest taste score supplies the reference recipe; equal scores favor the most recent cup. With one rating, the result explicitly acknowledges sparse evidence.

This path is deterministic and local. It makes no model request and uploads no history, scores or notes. Evidence labels come directly from saved records, and absent observations remain unknown. You may keep the reference recipe or experiment with one grind-setting step in either direction. Use or save the proposed recipe through the editor before brewing. Color, texture and flow never become inferred taste observations.

## Fill coffee details from a photo

In Add/Edit Coffee, choose a label photo, then tap **Fill coffee details from photo**. Existing saved photos work too. The resized, re-encoded photo is sent to OpenAI using your saved key; API charges may apply. Autofill reads the coffee name, roaster, origin and unambiguous roast date. Unknown fields remain unchanged. Readable fields replace the current form values, which you can review or correct before **Save**; **Cancel** discards changes. Expiry dates and uncertain dates should not be used as roast dates. An unreadable label shows an error and leaves the form unchanged.

Extraction uses the [official structured output format](https://developers.openai.com/api/docs/guides/structured-outputs). Automated checks cover the request schema, mocked extraction, field preservation, and invalid dates. Live label recognition still needs verification with an API key and actual coffee packaging.

## Choose on-device or OpenAI processing

**Settings → Photo recipes and label scanning → Processing** selects **On this iPhone** or **OpenAI**. The default is on-device processing, with no automatic cloud fallback. Only choosing OpenAI permits API requests. Key status errors stay inline and always end the loading state. The key form appears only when OpenAI is selected.

On-device photo features require iOS 26+ on an Apple Intelligence compatible device with the model enabled and downloaded. Apple Vision reads label text, then Foundation Models interprets the text. General visual analysis of beans is not performed locally. The journal itself supports iOS 17+. Rated-history suggestions do not require Apple Intelligence or an API key.

Generation quality, physical camera behavior, model availability and signed-device credentials require hands-on verification. 

## License

Groundwork is available under the [MIT License](LICENSE).
