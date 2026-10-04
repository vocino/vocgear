# VocGear

## Problem

Pawn tells you what's an upgrade but won't act on it. VocGear
is the muscle: equip upgrades, pick quest rewards, and advise
loot rolls, all from Pawn's verdicts - out of combat.

## Use

When a Pawn-flagged upgrade lands in your bags, VocGear equips it
and prints the margin. One equip per scan; the next bag update
handles the rest, so valuations stay correct as gear changes.

Rings and trinkets are announced by default; enable auto-equip
for them and VocGear takes the weaker slot.

Quest-complete dialogs get a printed pick (or auto-pick), and
group-loot rolls get a NEED/GREED recommendation in chat.

```
/vg          toggle on/off
/vg announce toggle chat lines
/vg config   open Settings > AddOns > VocGear
```

## Config

Settings > AddOns > VocGear, or `/vg config`:

- Enable auto-equip, chat announcements, audit mode (announce only)
- Minimum upgrade % (default 0.5, Pawn's own bar)
- Auto-equip rings and trinkets (default off)
- Include item-level upgrades (default on)
- Pawn scale picker (default any visible scale)
- Quest rewards: off / highlight / auto-pick (default highlight)
- Loot roll advisor (default on)

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
