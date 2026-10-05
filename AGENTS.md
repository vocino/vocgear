# AGENTS.md

## Code Map

- `main.lua`: the whole addon: bag scans, Pawn queries, equip rules, Settings panel, slash
- `VocGear.toc`: addon metadata (`RequiredDeps: Pawn`)
- `tests/run.lua`: stub-harness regression tests (`lua tests/run.lua`)
- `FAMILY.md`: conventions shared by every Voc addon
- `VERSIONING.md`: tag-driven semver releases (identical across the family)
- `.luacheckrc`: lint config declaring the addon's globals
- `.reference/pawn-analysis.md`: verified Pawn internals + harmony contract (gitignored)
- `.reference/`: local analysis checkouts, never packaged or committed
- `.github`: `test.yml` (tests + lint) and `release.yml` (packager)

## Family

VocGear is one of the Voc addons. Naming, slash grammar, chat voice,
settings, layout, and docs follow `FAMILY.md`; that file is identical
in every sibling repo, so edit it everywhere or not at all.

## Namespace

Every global carries the `VocGear` prefix: SavedVariables
(`VocGearDB`), slash (`SLASH_VOCGEAR*`), Settings variables
(`VocGear_*`), chat (`VocGear:` via `ns.say`). Module state lives on
`ns`. Never introduce an unprefixed global; `luacheck .` enforces it.

## Tests

Run `lua tests/run.lua` (Lua 5.1 or 5.4) and `luacheck .` from the
repo root after behavior changes. Both run in CI on every push.
Tests are excluded from the packaged addon (see `.pkgmeta`).

## Releases

Follow `VERSIONING.md` when cutting a release; never retag.

## Live testing

`_retail_\Interface\AddOns\VocGear` is a directory junction to this repo,
so edits go live on `/reload`. The client only loads `.toc`-listed files;
dev files (`tests/`, `.git`, docs) sitting in the folder are ignored.

Recreate: `New-Item -ItemType Junction -Path '<AddOns>\VocGear' -Target D:\Code\vocgear`
Remove: `Remove-Item '<AddOns>\VocGear'` (link only, never `-Recurse`)
