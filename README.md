# VocGear

Pawn tells you what's an upgrade but won't act on it. VocGear is the
muscle: when an upgrade lands in your bags, it equips it, out of
combat, and prints the margin. With
[Pawn](https://www.curseforge.com/wow/addons/pawn) installed, Pawn's
stat weights decide; without it, item level does. A small panel of
rules tunes what counts.

## Install

Download the latest zip from [GitHub
Releases](https://github.com/vocino/vocgear/releases) (also on
CurseForge and Wago), copy the folder into `Interface/AddOns`, and
make sure it is named `VocGear` (the folder name must match the
`.toc` file). The same package runs on Retail and on the Forever
client.

## Use

VocGear equips one upgrade per scan; the next bag update handles the
rest, so valuations stay correct as gear changes. Rings and trinkets
are announced by default; enable auto-equip for them and VocGear
takes the weaker slot.

A Check Bags button on the character sheet (next to Pawn's) re-runs
the check on demand. Changing any option rescans too. The addon
compartment on the minimap opens the settings.

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
- Prioritize set bonuses (default on)
- Pawn scale picker (default any visible scale)
- Equip sound (default the quest chime; Off available)
- Character sheet button (default on)

The panel's first line says which source is deciding: Pawn, or the
built-in item-level check.

## How it works

Every bag item goes through Pawn's own upgrade check (or, without
Pawn, a plain item-level comparison against what you wear), filtered
by your scale, threshold, and item-level choices. Single-slot upgrades
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
- `VocGear.toc` / `VocGear_Forever.toc`: metadata for Retail and the Forever client
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
[VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear) ·
[VocXP](https://github.com/vocino/vocxp) ·
[VocVendor](https://github.com/vocino/vocvendor)
