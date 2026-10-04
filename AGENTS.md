# AGENTS.md

## Code Map

- `main.lua` — the whole addon: scan bags, ask Pawn, equip
- `VocGear.toc` — addon metadata (`OptionalDeps: Pawn`)
- `tests/scan_test.lua` — stub-harness regression tests (`lua tests/scan_test.lua`)
- `VERSIONING.md` — tag-driven semver releases (same scheme as vocwarbank)
- `.reference/pawn-analysis.md` — verified Pawn internals + harmony contract (gitignored)
- `.reference/` — local analysis checkouts, never packaged or committed
- `.github` — project configuration
