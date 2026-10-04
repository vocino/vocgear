# VocGear

## Problem

Pawn tells you what's an upgrade but won't equip it. Zygor's Gear
Advisor auto-equips, but it's bundled inside a guide suite. VocGear
is the one job: equip what Pawn flags, out of combat, no UI.

## Install

Copy the `VocGear` folder into `Interface/AddOns`. Requires Pawn —
it does the scoring, VocGear just equips.

## Use

When a Pawn-flagged upgrade lands in your bags, VocGear equips it
and prints a line. One equip per scan; the next bag update handles
the rest, so valuations stay correct as gear changes.

Rings and trinkets are announced, never auto-equipped: with two
slots, a blind equip can replace the better one.

```
/vg          toggle on/off
/vg announce toggle chat lines
```

## What's inside

- `main.lua`: the whole addon — scan bags, ask Pawn, equip
- `VocGear.toc`: metadata
- `tests/scan_test.lua`: stub-harness regression tests, no WoW client needed

## Tests

```
lua tests/scan_test.lua
```

## License

MIT
