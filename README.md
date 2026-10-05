# VocGear

## Problem

Pawn tells you what's an upgrade but won't act on it. VocGear
is the muscle: equip what Pawn flags, out of combat,
with a small panel of rules to tune it.

## Use

When a Pawn-flagged upgrade lands in your bags, VocGear equips it
and prints the margin. One equip per scan; the next bag update
handles the rest, so valuations stay correct as gear changes.

Rings and trinkets are announced by default; enable auto-equip
for them and VocGear takes the weaker slot.

A Check Bags button on the character sheet (or `/vg scan`)
re-runs the check on demand; changing options rescans too.

```
/vg          toggle on/off
/vg announce toggle chat lines
/vg config   open Settings > AddOns > VocGear
/vg scan     check bags now
```

## Config

Settings > AddOns > VocGear, or `/vg config`:

- Enable auto-equip, chat announcements, audit mode (announce only)
- Minimum upgrade % (0-25 in 5s, default 0 = everything Pawn flags)
- Auto-equip rings and trinkets (default off)
- Include item-level upgrades (default on)
- Don't replace heirlooms (default on)
- Pawn scale picker (default any visible scale)
- Character sheet button (default on)

## What's inside

- `main.lua`: the whole addon - scan bags, ask Pawn, equip + advise
- `VocGear.toc`: metadata
- `tests/scan_test.lua`: stub-harness regression tests, no WoW client needed

## Tests

```
lua tests/scan_test.lua
```

## License

MIT

---

Part of the Voc family: tiny addons that do one job.
