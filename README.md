# Attic

A Mac app for your Apple Photos library: find duplicates, clean up retakes,
and pick the best photos from every trip and event. Everything runs on your
Mac. Your photos are never uploaded anywhere.

![Attic icon](docs/icon.png)

## What it does

- **Duplicates.** The same picture more than once (re-saves, WhatsApp copies,
  double imports), even years apart. Attic keeps the original.
- **Retakes.** When you took five shots to get one right, Attic groups them and
  suggests the keeper, with a one-line reason: eyes open, sharpest, better
  framed.
- **Best of.** Your library grouped into events by time, place and activity
  (beach, mountains, food, concerts…), with three picks suggested for each.
  Export the ones you like to `~/Pictures/best-of/`.
- **One careful delete.** Nothing is deleted until you press "Delete from
  Photos…". Photos asks you to confirm, and deleted photos stay in Recently
  Deleted for 30 days.

Your decisions are remembered, so a rescan only asks about new photos.

## Privacy

- Photos are analysed on your Mac with Apple's Vision framework.
- Nothing is uploaded, and photos that are only in iCloud aren't downloaded
  for analysis.
- One setting is off by default: "Name places with Apple Maps" sends each
  event's approximate location to Apple to name it.

## Install

Requires macOS 15 or later on an Apple Silicon Mac.

1. Download `Attic-<version>.dmg` from
   [Releases](../../releases), open it, and drag Attic to Applications.
2. The first time you open it, macOS says it can't verify the app. Attic isn't
   notarized by Apple yet. Open **System Settings › Privacy & Security**,
   scroll down, and click **Open Anyway** next to Attic.
3. Allow access to your photo library when asked.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`). Xcode itself
isn't needed.

```sh
./check.sh      # tests and checks
./deploy.sh     # build and install to ~/Applications
./release.sh    # build a DMG into dist/
```

See [AGENTS.md](AGENTS.md) for how it works.

## License

MIT. See [LICENSE](LICENSE).
