# showcase

The author's site reads this folder (its projects page) to show attic. Keep it current whenever
the app's look, name or status changes, and bump `updated` when you do.

- `showcase.json`: name, line (under 110 characters, for a stranger), public,
  updated. No `url` or `repo`: `scripts/public-check.sh` keeps the owner's
  handle out of this repo, so the site supplies the release and GitHub links.
- `light.png`, `dark.png`: 1280×800, the app's own content edge to edge.

## Regenerate

```sh
showcase/shoot.sh
```

Builds a debug app, generates the illustrated demo library (`--make-demo`, drawn in code, no real photos), opens Best of in the background at 1280×800 in each look and captures the window without its shadow (`window-check.swift --save-plain`). Needs Screen Recording for the terminal.
