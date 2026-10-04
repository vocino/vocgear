# AGENTS.md

## Code Map

- `main.lua` — the whole addon: bag scans + Settings panel
- `VocGear.toc` — addon metadata (`OptionalDeps: Pawn`)
- `tests/scan_test.lua` — stub-harness regression tests (`lua tests/scan_test.lua`)
- `VERSIONING.md` — tag-driven semver releases (same scheme as vocwarbank)
- `.reference/pawn-analysis.md` — verified Pawn internals + harmony contract (gitignored)
- `.reference/` — local analysis checkouts, never packaged or committed
- `.github` — project configuration

## Live testing

`_retail_\Interface\AddOns\VocGear` is a directory junction to this repo,
so edits go live on `/reload`. The client only loads `.toc`-listed files;
dev files (`tests/`, `.git`, docs) sitting in the folder are ignored.

Recreate: `New-Item -ItemType Junction -Path '<AddOns>\VocGear' -Target D:\Code\vocgear`
Remove: `Remove-Item '<AddOns>\VocGear'` (link only — never `-Recurse`)
