# VocGear

Pawn tells you what's an upgrade but won't act on it. VocGear is the
muscle: when a Pawn-flagged upgrade lands in your bags, it equips it,
out of combat, and prints the margin. A small panel of rules tunes
what counts. Requires [Pawn](https://www.curseforge.com/wow/addons/pawn).

## Install

Download the latest zip from [GitHub
Releases](https://github.com/vocino/vocgear/releases) (also on
CurseForge and Wago), copy the folder into `Interface/AddOns`, and
make sure it is named `VocGear` (the folder name must match the
`.toc` file).

## Use

VocGear equips one upgrade per scan; the next bag update handles the
rest, so valuations stay correct as gear changes. Rings and trinkets
are announced by default; enable auto-equip for them and VocGear
takes the weaker slot.

A Check Bags button on the character sheet (next to Pawn's) re-runs
the check on demand. Changing any option rescans too.

```
/vg            toggle auto-equip on/off
/vg on|off     set auto-equip explicitly
/vg scan       check bags now
/vg announce   toggle chat announcements
/vg config     open Settings > AddOns > VocGear
/vg help       this list (/vocgear works too)
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

## How it works

Every bag item goes through Pawn's own upgrade check, filtered by
your scale, threshold, and item-level choices. Single-slot upgrades
equip at once; two-slot items (rings, trinkets) equip into the slot
Pawn names, the empty slot, or the weaker one, and are only announced
unless you opt in. A loop guard leaves freshly displaced gear alone
for 30 seconds and pauses auto-equip for a minute if the same slot
flips three times, so two scales can never fight over one item.
Weapon swaps that cross the melee/ranged line (a sword for a
hunter's bow) are announced, never auto-equipped. A Unique-Equipped ring or
trinket whose twin is already worn is announced instead of equipped.

## What's inside

- `main.lua`: the whole addon: scan bags, ask Pawn, equip or advise
- `VocGear.toc`: metadata
- `tests/run.lua`: stub-harness regression tests, no WoW client needed

## Tests

```
lua tests/run.lua
luacheck .
```

## License

MIT

---

Part of the Voc family: tiny addons that do one job.
Siblings: [VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear)
