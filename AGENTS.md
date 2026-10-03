# Attic

```sh
./check.sh     # tests, app bundle, section snapshots, real-window checks, e2e walks, public-safety scan
./deploy.sh    # check, build release, install ~/Applications/Attic.app
./release.sh   # on a v* tag: check, build, package dist/Attic-<version>.dmg (+ Attic.dmg); --publish to release
```

If a `NOTES.local.md` exists next to this file, read it too. It holds the
owner's private notes and is never committed.

## What it is

A native Mac app (SwiftUI + PhotoKit) for looking after an Apple Photos
library. It's named for the place you clear out and find the treasures in:
cleanup and keeping the best are the two halves of the app. Each job is a
sidebar section, so more tools can slot in later.

- **Duplicates**: the same picture more than once (re-saves, messaging-app
  copies, double imports), at any time apart. Keeper: favourite, then edited,
  then largest, then oldest.
- **Retakes**: several tries at one moment. Keeper chosen by faces, sharpness,
  exposure, composition and resolution, with a one-line reason.
- **Best of**: events by time, place and activity (beach, mountains, food,
  concert…), with three picks suggested each. Export sends ticked photos to
  `~/Pictures/best-of/`, with a `manifest.json`.
- **Marked for deletion**: everything you marked, deleted in one batch.
  Photos asks you to confirm, and deleted photos stay in Recently Deleted for
  30 days.

Hard boundaries:
- **Photos stay on the Mac.** Analysis is Apple Vision, on-device. The one
  exception is opt-in: "Name places with Apple Maps" sends each event's
  approximate location to Apple.
- **No iCloud downloads for analysis.** It uses the previews already on the
  Mac, falling back to smaller ones. Export fetches originals only for the
  photos you tick.
- **Exports keep the date taken and GPS, nothing else.** No camera, lens or
  serial numbers. At most 2400 px.
- **Nothing is deleted without Photos' own confirmation**, and never one by one.
- **Agents never look at the owner's photos.** Check the look with
  `--snapshot` on the synthetic fixture, and check real runs through
  `~/Library/Application Support/Attic/last-run.json`, which holds counts only.

## How to run

- Requirements: macOS 15 or later on Apple Silicon, and the Xcode Command Line
  Tools (Xcode itself isn't needed).
- The app: `./deploy.sh`, then `open ~/Applications/Attic.app`. The first
  launch asks for Photos access. Each rebuild changes the ad-hoc signature, so
  macOS may ask again.
- State: `~/Library/Application Support/Attic/`.
  - `state.json`: decisions per photo, Best of ticks and names, the
    place-name setting.
  - `features.json`: the analysis cache, keyed by photo id and modification
    date.
  - `last-run.json`: counts only.
- Overrides: `ATTIC_HOME`, `ATTIC_BEST` (export folder), `ATTIC_FIXTURE` (use a
  folder library instead of Photos), `ATTIC_SCRIPT` (scripted actions; fixture
  only). Steps are listed in `Sources/AtticKit/Script.swift`; `type:<keys>`
  sends keystrokes through the app's own event queue, so the real window's
  keyboard shortcuts can be tested.
- The binary also runs as a tool:
  - `Attic --make-fixture <dir>` writes the synthetic library (generated
    shapes, designed feature prints, GPS in the files).
  - `Attic --snapshot <out> <fixture>` renders every section, light and dark,
    to PNG.
  - `Attic --make-icon <png>` draws the icon. It's drawn in code, so there's no
    binary asset.
  - `Attic --make-demo <dir>` writes the illustrated demo library (beach,
    mountains, city, food and a re-saved sunset, all drawn in code) used for
    the README screenshots. `scripts/screenshots.sh` captures the real window
    on it into `docs/screenshots/` (with `window-check.swift --save`). It needs
    Screen Recording permission.

Build pieces, all of which work with just the Command Line Tools:
- `swift build` compiles.
- `scripts/build-app.sh` wraps it into `dist/Attic.app`: Info.plist, icon via
  `sips` and `iconutil`, and an ad-hoc `codesign` with id `app.attic.mac`.
- `scripts/test.sh` is `swift test`, plus the Command Line Tools' Testing
  framework path when Xcode isn't selected (plain `swift test` fails there
  with "no such module Testing"). With Xcode it's plain `swift test`.

## How to verify

`./check.sh` runs these steps:
1. `AtticCoreTests`: grouping, ranking, events, naming and state.
2. `AtticKitTests`: every flow through `AppModel` on the fixture (confirm,
   delete everything in a group, undo, relaunch memory, one-batch delete,
   cancelling Photos' prompt, export keeping GPS but not the camera,
   re-export, rename moving the folder), plus real Vision on a synthetic image.
3. Builds the bundle and renders 7 snapshots.
4. **The real window** (`scripts/window-check.swift`): opens the app in the
   background (it never takes the keyboard) on the fixture with scripted
   actions (for example `section:marked,confirm-all,delete`), captures the
   window, and fails if it drew blank. A blank window scores about 100 colours
   from edge shading; a drawn one 800 or more. The threshold is 300. With
   `--expect`/`--reject` it also reads the window's text with Vision, on-device:
   the demo library's first section on launch must show its 1 duplicate group.
   It needs Screen Recording permission for the terminal, and without it the
   check says it was skipped.
5. **e2e walks** (`scripts/e2e.swift`, about 10 s): each walk opens Attic in the
   background on a fresh copy of the demo library and uses it through the
   accessibility API, as VoiceOver would: it presses buttons, selects sidebar
   rows, chooses menu items, types into the rename field and reads the text
   back, waiting for each expectation rather than sleeping. Keyboard shortcuts
   go through `type:`. It never moves the mouse or takes the keyboard. Walks:
   `first-launch`, `duplicates-by-clicks` (keep/delete pills, mark, keep all,
   skip, each undone from Edit ▸ Undo, banner dismiss), `keyboard` (j, a,
   space, return after a section switch), `retakes-marked-delete` (not
   retakes, mark, keep instead, the one-batch delete), `best-of-export-rename-skip`
   (pick, export with files on disk, rename, skip, the filter, reopen) and
   `menus-and-rescan` (Go ▸ each section, File ▸ Rescan keeping decisions).
   Run one: `swift scripts/e2e.swift dist/Attic.app keyboard`. Needs
   Accessibility permission for the terminal; without it, it says it was
   skipped.
6. **Public-safety scan** (`scripts/public-check.sh`): fails if a tracked file
   or any commit contains a pattern from the git-ignored `.public-denylist`
   (one regex per line). With no denylist, it says it was skipped.

Tests are named for the rule they hold. Views are thin: every button calls an
`AppModel` method, and the tests call those same methods.

What `check.sh` can't cover: real mouse clicks and drags (the walks press
controls through accessibility instead); the zoom sheet, opened by a tap with
no accessibility action; "Name places with Apple Maps" (never pressed, it
would send locations to Apple); the Photos-access-denied page; and the PhotoKit calls themselves (access, delete, iCloud
originals). Check those by hand after `./deploy.sh`, and read `last-run.json`.

## How it decides

The thresholds were set on a real ~650-photo library from the numbers. They
live in `Grouping.Tuning`, with notes.
- **Distance** is the Vision feature-print distance (unit vectors, 0 to 1.4).
  - Duplicates: at most 0.15, with difference hashes within 5 bits.
  - Retakes: average linkage cut at 0.45, and no pair in a group more than
    0.72 apart. 0.10 comes off the distance when shots are within 5 min, and
    0.03 within an hour. Time only nudges, because timestamps lie.
- **Ranking** scales each signal within the group, with a minimum spread per
  signal, so a 1% wobble never decides a keeper. A favourite always wins, and a
  signal nobody has adds nothing.
- **Events** split on 8 h gaps. Runs within 36 h and 150 km of each other merge
  into a trip when they're away from home. Home is the ~11 km cell with the
  most photos.
  - Name: place (if opted in), otherwise the activity, then the dates.
  - Activity: the Vision label group shown in at least 30% of the event.
- **Memory**: decisions are per photo in `state.json`. A group whose photos
  were all decided isn't shown again. When a new shot joins, the old ones show
  as "kept before". Skip is for this session only.

## Measured (2026-10-03, Apple M4)

- Grouping on synthetic libraries (768-number prints, bursts of retakes, 3%
  copies; no real photos): 5k photos 0.06 s, 20k 0.67 s, 50k 3.9 s. Events:
  0.05 s, 0.18 s, 0.45 s.
- Vision: about 13 ms per photo at 512 px, one at a time. The analyzer runs six
  at once, and the cache means only new or edited photos are looked at again.
  How long PhotoKit takes to hand over previews isn't measured (that needs a
  real library).
- The app: 3.0 MB with symbols (v0.1.3), about 1.9 MB stripped (from v0.1.4).

## Known gaps

Measured or confirmed, deliberately not fixed yet:
- **Every decision rebuilds the whole grouping on the main thread** (`record`
  and `undo` call `rebuild`). From the numbers above, that's about 0.85 s per
  click at 20k photos and about 4.3 s at 50k. The fix is to keep the near pairs
  from the scan and only re-filter on a decision.
- **No live library updates.** Photos added or deleted in Photos while Attic
  is open show up only after Rescan (⌘R); there's no PhotoKit change observer.
- **Thresholds come from one ~650-photo library.** Larger or very different
  libraries may want different cuts.
- **Decisions are per Mac.** `state.json` is local, so a second Mac on the
  same iCloud library starts fresh.
- Videos, Live Photo motion and iCloud-only photos (no preview on the Mac) are
  not looked at; the sidebar counts the iCloud-only ones.

## Deploy

- `./deploy.sh` installs to `~/Applications`. It refuses while Attic is open.
- Versions come from git. Every build (`deploy.sh` too) takes the latest `v*`
  tag, with `-dev` once the code has moved past it, so the installed app
  always says which code it is.
- `./release.sh` refuses unless HEAD is exactly a `v*` tag with a clean tree.
  It builds `dist/Attic-<version>.dmg` (the app plus an Applications link) and
  a copy named `Attic.dmg`, so the repo's
  `releases/latest/download/Attic.dmg` link always serves the newest one. The
  README links it relatively (`../../releases/…`), so no account name sits in
  the files. It also scans the built app for private data.
- To publish: `git tag -a v<next> -m "<what changed, for people>"` then
  `./release.sh --publish`. That pushes main and the tag and creates the
  GitHub release with both DMGs; the tag's message becomes its "What's new".
  `--publish` refuses a tag without a message.
- The app is ad-hoc signed, not notarized. On another Mac, macOS blocks the
  first launch: open System Settings › Privacy & Security and click **Open
  Anyway**. The README and release notes say so.
- Use `SKIP_CHECK=1` only when the deploy itself is the fix, and say so in the
  commit.

## Deferred (don't build unless asked)

- Developer ID signing and notarization. It needs an Apple Developer Program
  membership; `notarytool` and `stapler` are already in the Command Line Tools.
- Intel (x86_64) builds. A universal binary needs Xcode's build system.
- Homebrew cask, `.pkg` installer, auto-update.
- A local model tie-breaker: tried in the prototype, slow, and it never changed
  a keeper.
- Videos and Live Photo motion.
- Real mouse clicks and drags in the e2e walks (CGEvent would take over the
  mouse while someone works; accessibility presses cover every button).

## Learned the hard way

- **Photos over AppleScript is not a foundation.** The prototype drove Photos
  with photoscript, which hung in `NSAppleScript compileAndReturnError` on a
  server thread. Moving it to a child process then hit Photos going silent
  after a relaunch. PhotoKit has neither problem.
- **PhotoKit returns nothing for `.highQualityFormat`** when only a small
  preview is on the Mac. That was 114 of 793 photos on the first real library.
  Fall back to `.fastFormat`, still without network.
- **Views must read observed state.** `StateStore` is a plain class. Views that
  read it directly never redrew (the Marked page said "Nothing marked" while
  the sidebar said 5). AppModel keeps an observed copy, and every write goes
  through `save`.
- **A banner with `fixedSize(vertical:)` next to a `Spacer` blanked the whole
  window**, sidebar included, the moment a message appeared, which was right
  after the first real delete. AppKit logged "layoutSubtreeIfNeeded on a view
  which is already being laid out". Unit tests and snapshots can't see this;
  `window-check` can.
- **Synthetic shapes all look alike to Vision.** Fixture photos carry designed
  feature prints (`features.json`). Grouping is proven in the core tests with
  exact distances, and Vision gets its own test.
- **ImageRenderer can't draw native controls** (toggles and segmented pickers
  show 🚫 in snapshots), and dynamic `NSColor`s resolve against the drawing
  appearance. Snapshots set both the colour scheme and `NSAppearance`.
- **ImageIO drops `TIFFDateTime` when re-encoding.** Write
  `ExifDateTimeOriginal`.
- **Export file names must be path-safe.** A `/` in an id prefix pointed at a
  folder that didn't exist.
- **Judge an icon at Dock size, next to real icons.** The first "window" icon
  read as a pale disc with specks at 55 pt. The fix was one bold shape, prints
  two to three times bigger, no thin lines, and stronger colours. Then the
  teal wall went too: golden light filling the whole rounded square, and the
  prints. (macOS 26 puts icons that do not fill the square into a grey tile.)
- **`exit()` skips `defer`.** The window check left test apps running until
  every exit went through one function that closes them.
- **A test launch must never take the keyboard.** The "stale first section"
  (2026-09-26: Duplicates said "0 groups · No duplicates left to review") was
  no render bug. The capture launched Attic in front while the owner was
  typing elsewhere; the Duplicates list takes focus on appear, and one `s`
  (skip) or `a` (keep all) emptied it. The sidebar in that frame agreed (no
  count by Duplicates), which is what gave it away. Window checks now open the
  app with `activates = false`, and drive keys only through `type:`.
- **SwiftUI's accessibility tree is empty from inside the app.** It builds the
  tree only for an outside client, so the e2e walks drive Attic from a second
  process with the accessibility API, which also needs no focus.
- **Focus set in `onAppear` was lost on a section switch.** The new list wasn't
  in the window yet, focus fell back to the window, and every shortcut went
  nowhere after ⌘2 or the Go menu. The keyboard walk caught it; focus is now
  set one runloop turn later.
- **`build-app.sh` used to hide compile errors** (swift build prints them to
  stdout) and left the previous `dist/Attic.app` in place, so a broken build
  looked like a running one. It now prints the errors and exits 1.
