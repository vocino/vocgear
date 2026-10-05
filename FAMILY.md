# The Voc family

Tiny World of Warcraft addons that each do one job, install
independently, and feel like one product when they meet. This file
is the contract that makes that true. It is kept word-for-word
identical in every Voc repository: change it in one, copy it to all.

## Members

| Addon | Job | Slash | Repo |
| --- | --- | --- | --- |
| VocWarbank | Audit the warband bank, bank, and bags; draw the line; clean house | `/vw`, `/vocwarbank` | https://github.com/vocino/vocwarbank |
| VocGear | Equip what Pawn says is an upgrade, out of combat | `/vg`, `/vocgear` | https://github.com/vocino/vocgear |

## Principles

1. **One job.** An addon does one thing a player can say in a
   sentence. New ideas become new addons, not new tabs.
2. **Nothing is lost silently.** Destroying, selling, mailing, or
   trading away value always goes through a confirmation. Reversible
   actions (equipping gear) may run automatically, but they are
   announced and have an audit mode that only reports.
3. **Out of combat, out of the way.** Nothing acts during combat
   lockdown. No minimap buttons, no login spam, no popups the player
   did not ask for.
4. **Guests, not dependencies.** Other addons are optional unless the
   addon is meaningless without them (VocGear needs Pawn). Every
   external call is presence-gated and `pcall`-guarded; a broken
   neighbor never breaks us. Suites that skin the UI are adopted when
   present and never required.
5. **Settings apply live.** Changing an option in the panel or on the
   slash line takes effect immediately, with no reload.
6. **Stock first.** Default chrome is Blizzard's own, so the addon
   looks native beside the game's windows and beside its siblings.
   Data colors (item quality, verdicts) are ours and stay the same in
   every look.
7. **Headless tests, always green.** Behavior lives behind `ns.*`
   functions that stubbed WoW APIs can drive. No release ships red.

## Naming

- The addon name is `Voc` + one word in CamelCase: `VocWarbank`,
  `VocGear`. The folder, `.toc`, and `## Title` match exactly.
- Every global carries the addon name. SavedVariables are
  `<Name>DB`. Named frames are `<Name>Something`. Static popups are
  `<NAME>_SOMETHING`. Settings variables are `<Name>_key`. Never
  introduce an unprefixed global.
- Each file begins `local name, ns = ...` (or `local _, ns = ...`
  when the name is unused) and puts state on `ns`, never on `_G`.
- The slash command has a short form (`/v` + one letter) and the
  full name as a long form (`/vocgear`). Both are documented.

## Slash grammar

```
/<short>              the one main action (open the window, toggle on/off)
/<short> config       open Settings > AddOns > <Name>
/<short> help         list every subcommand
/<short> <sub> ...    further subcommands, lower-case, case-insensitive input
```

Anything unrecognized prints help; it never performs an action, so a
typo can never toggle, sell, or equip. Help prints one subcommand
per line, the command padded so descriptions line up.

## Chat voice

Chat lines go through `ns.say(msg)`, which prints the addon name as
a colored prefix followed by the message:

```lua
ns.PREFIX_COLOR = "ff66ccff"   -- the family color, same everywhere
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end
```

One line per event. Announce-once per session for advice that would
otherwise repeat on every scan. Lower-case first word after the
prefix ("equipped ...", "price source set to ..."). Every line is a
fact or a next step, never a greeting.

## Settings

- Account-wide SavedVariables holding a flat table of options.
- A `defaults` table is the single source of truth. On load, missing
  keys are filled, and any key holding the wrong type or an
  out-of-range value is reset to its default. Unknown keys are left
  alone for forward compatibility.
- The panel is a native Blizzard Settings category registered with
  `Settings.RegisterVerticalLayoutCategory("<Name>")`, built from
  `Settings.RegisterAddOnSetting` plus `CreateCheckbox`,
  `CreateSlider`, and `CreateDropdown`. No hand-drawn canvas panels.
- Free-text options (names, keys) live on the slash line, and the
  panel says so.
- `/<short> config` opens the category; when the Settings API is
  missing it says where to find the panel instead of erroring.

## Repository layout

```
<Name>/
  <Name>.toc            metadata (template below)
  *.lua                 the addon; one file or a few, never a framework
  tests/run.lua         headless tests, run with `lua tests/run.lua`
  README.md             user docs (template below)
  AGENTS.md             contributor map, namespace, tests, releases
  FAMILY.md             this file
  VERSIONING.md         tag-driven semver releases
  LICENSE               MIT
  .pkgmeta              package-as + ignore list for dev files
  .luacheckrc           lint config declaring the addon's globals
  .gitignore            `.reference/` local analysis checkouts
  .github/workflows/
    test.yml            tests + luacheck on every push and PR
    release.yml         BigWigsMods packager on `v*` tags
```

No embedded libraries (Ace3 and friends). The whole addon stays
readable in one sitting.

### `.toc` template

```
## Interface: <current retail build>
## Title: <Name>
## Notes: <one sentence, what it does>
## Author: vocino
## Version: @project-version@
## Category: Bags & Inventory
## IconTexture: Interface\Icons\<an existing game icon>
## SavedVariables: <Name>DB
## RequiredDeps / OptionalDeps: ...
## X-Website: https://github.com/vocino/<name>
## X-License: MIT
## X-Curse-Project-ID: <id>
## X-Wago-ID: <id>
```

`## Version` is never hand-edited; the packager fills it from the tag.

## Tests and lint

- Tests are plain Lua with stubbed WoW APIs, written for Lua 5.1 (the
  client's dialect) and passing on 5.4 as well. `lua tests/run.lua`
  from the repo root exits non-zero on failure.
- `luacheck .` passes with the repo's `.luacheckrc`, which lists the
  WoW globals the addon reads and the globals it owns
  (SavedVariables, `SLASH_*`).
- `test.yml` runs both on every push and pull request.

## Releases

See `VERSIONING.md` (identical in every repo): tag-driven semver,
`v*` tags trigger the packager, tags are never moved. Commit subjects
are the changelog, so write `feat:`, `fix:`, `docs:`, `chore:`,
`test:`, `refactor:` lines a player can read.

## Documentation

`README.md` sections, in order: the pitch (one paragraph), Install,
Use (with the slash block), Config, How it works, What's inside,
Tests, License, and the family footer:

```
---

Part of the Voc family: tiny addons that do one job.
Siblings: [VocWarbank](https://github.com/vocino/vocwarbank) ·
[VocGear](https://github.com/vocino/vocgear)
```

`AGENTS.md` sections: Code Map, Family (pointer to this file),
Namespace, Tests, Releases, Live testing.

## Adding an addon

1. Copy the layout above from a sibling, rename everything.
2. Add a row to Members here, then copy this file to every sibling.
3. Add the sibling link to every README footer.
4. Register CurseForge and Wago projects, fill in the `.toc` ids and
   the workflow secrets.
