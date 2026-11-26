# Dyrutilities — Specification

**Status:** v0.1 draft, 25 November 2026. This version covers the framework and
the primary menu only; no features exist yet.
**Target client:** WoW Forever 1.60.1, Interface `16001` (reported, not yet
measured; see §8).
**Author / maintainer:** Clayton.

---

## 1. Purpose

A personal collection of utility changes, tools and quality-of-life fixes for
WoW Forever, possibly published later. Each feature is an independent
**submodule** with its own settings. One window lists them with a checkbox
each. **Every feature defaults to off.**

### 1.1 Non-goals for v0.1

- No actual features. v0.1 is the framework, the menu, the probe and the tests.
- No other clients. Forever only (D-1).
- No libraries (D-3).

---

## 2. Decision log

Every design decision, who made it, and when. Rows marked **Claude default**
were chosen to keep moving and are open to change. Confirm or overturn them.

| # | Decision | Outcome | By | Date |
|---|---|---|---|---|
| D-1 | Target client | WoW Forever 1.60.1 only. Interface `16001`, single TOC | User | 25 Nov 2026 |
| D-2 | Relationship to DyrueWoWTools | Port its Core (module registry, DB, Errors, Compat, Widgets, probe and test patterns) as a base. The two addons stay independent afterwards | User | 25 Nov 2026 |
| D-3 | Libraries | None. Plain frames and SavedVariables | User | 25 Nov 2026 |
| D-4 | Storage scope | Per-character, for everything: enabled state, module settings, window state. `SavedVariablesPerCharacter` only | User | 25 Nov 2026 |
| D-5 | Where the menu lives | Our own standalone window, plus a stub entry in Blizzard's Options › AddOns that opens it | User | 25 Nov 2026 |
| D-6 | Where module settings appear | Same window: feature list on the left, the selected feature's details and settings on the right | User | 25 Nov 2026 |
| D-7 | Toggle semantics | Live where possible. A module that cannot cleanly apply a change without a reload declares so, and the window offers a Reload button | User | 25 Nov 2026 |
| D-8 | Ways to open the menu | Slash command, and the minimap addon compartment. No minimap button, no keybinding. **Amended 25 Nov 2026:** Forever's minimap shows no compartment button (COMPAT_FINDINGS), so in practice the routes are the slash command and the Options page. The TOC registration is kept because it is harmless, but it is not advertised anywhere | User | 25 Nov 2026 |
| D-9 | Slash commands | `/dyru` and `/dyrutilities` | User | 25 Nov 2026 |
| D-10 | Probe packaging | A separate `Dyrutilities_Probe` addon (`/dyruprobe`), never shipped in a release | User | 25 Nov 2026 |
| D-11 | Tests and tools | Port DyrueWoWTools' headless Lua 5.1 test harness and `sync.ps1` now | User | 25 Nov 2026 |
| D-12 | Git workflow | Claude may commit, push and open PRs when asked, with standard attribution | User | 25 Nov 2026 |
| D-13 | Window look | Flat, hand-drawn box (DyrueWoWTools style), not Blizzard frame templates. The probe reports which Blizzard templates exist, so switching later is an informed choice | **Claude default** | 25 Nov 2026 |
| D-14 | Settings while a feature is off | Visible and editable. They take effect when the feature is turned on | **Claude default** | 25 Nov 2026 |
| D-15 | Account-wide storage | Not built. Added only when a module actually needs to share data between characters (that would also amend D-4) | **Claude default** | 25 Nov 2026 |
| D-16 | Escape key | Closes the menu window (registered in `UISpecialFrames`) | **Claude default** | 25 Nov 2026 |
| D-17 | TOC file name | Plain `Dyrutilities.toc`, not `Dyrutilities_Forever.toc`. With one client there is nothing to select between | **Claude default** | 25 Nov 2026 |
| D-18 | Module documentation | Each module lives in its own directory `Modules/<Name>/` with a `README.md` explaining it functionally and technically (§5.4). Enforced by `Tests/run_tests.py` | User | 26 Nov 2026 |

---

## 3. Client facts

What is known about the client, and how well it is known. Measurements go in
`COMPAT_FINDINGS.md`, and this table is updated to point at them.

| Fact | Source | Confidence |
|---|---|---|
| Forever is Mainline-family: "the vast majority of APIs available in 12.1.5" | warcraft.wiki.gg, Patch 1.60.1 API notes | Reported (beta-era notes) |
| Midnight's addon restrictions, including **secret values**, are active | same; probe 25 Nov 2026 | **Measured**: `issecretvalue` etc. present, and `UnitHealth("player")` is secret **even out of combat**. Any unit-data feature must be designed around secrets and probed first |
| Interface number `16001` | warcraft.wiki.gg TOC format page; 35 installed Forever addons; probe | **Measured**: `16001` (a number), build `71139` |
| Project ID | probe | **Measured**: `WOW_PROJECT_ID = 18 = WOW_PROJECT_CAMELOT`. There is no `WOW_PROJECT_FOREVER` |
| `## AddonCompartmentFunc` is supported | TOC format page; probe; by eye | **Measured**: we are in `AddonCompartmentFrame.registeredAddons`, but **Forever's minimap shows no compartment button**, so the entry cannot be reached |
| `_Forever` / `_Camelot` TOC suffixes are accepted | 1.60.1 notes, Beta 4 | Reported; unused (D-17) |
| Lua `require` renamed to `import` | 1.60.1 notes | Reported; irrelevant to us |
| `Settings.RegisterCanvasLayoutCategory` and friends exist | probe | **Measured**: present, and registration succeeds. The legacy `InterfaceOptions_*` API is absent |
| Templates: `UIPanelButtonTemplate`, `UIPanelCloseButton`, `UICheckButtonTemplate` | probe | **Measured**: present, along with 11 others including `PortraitFrameTemplate` and `ButtonFrameTemplate` (relevant to D-13) |
| AddOns folder is `World of Warcraft\_forever_\Interface\AddOns` | third-party guide; the folder exists on the dev machine | Likely |

**Rule:** no feature may rest on a "Reported" or "Unknown" row without a probe
that confirms it.

---

## 4. Architecture

```
Dyrutilities/
├── Dyrutilities.toc
├── Core/
│   ├── Compat.lua      ★ the only file that calls version-sensitive APIs
│   ├── Errors.lua      chat output + per-context circuit breaker
│   ├── DB.lua          the per-character SavedVariables
│   ├── Module.lua      submodule registry and lifecycle
│   ├── Widgets.lua     shared UI primitives
│   └── Core.lua        bootstrap, slash commands, compartment entry
├── UI/
│   ├── MainWindow.lua  the primary menu
│   └── SettingsStub.lua  the Options › AddOns entry
├── Modules/            one directory per feature (none yet), §5.4
│   └── <Name>/
│       ├── <Name>.lua  registers the module; more files if needed
│       └── README.md   functional + technical explanation (required)
├── Probe/Dyrutilities_Probe/   separate addon; not shipped
├── Tests/              headless Lua 5.1 suite + static checks
├── Tools/sync.ps1      copies/links into the Forever AddOns folder
└── Documents/          SPEC.md, COMPAT_FINDINGS.md
```

Load order (TOC): Compat → Errors → DB → Module → Widgets →
`Modules/<Name>/*.lua` → UI → Core. Modules register at file load. Core's bootstrap runs on events.

### 4.1 Lifecycle

| Event | What happens |
|---|---|
| File load | Each module calls `ns:RegisterModule`. Nothing touches SavedVariables yet |
| `ADDON_LOADED` (ours) | `DB:Initialize()`, then every module's `Initialize`: its settings table is filled from `defaults`, then `OnInitialize` runs |
| `PLAYER_LOGIN` | Every module whose stored state is *on* and which is available is enabled (`OnEnable`). Settings stub registered. First-run message once per character |
| Checkbox / slash toggle | §5.3 |

### 4.2 Compat rule

Inherited from the sibling addons: **feature-probe, never version-check.** No
code outside `Core/Compat.lua` calls an API whose existence or shape is
uncertain, and every such call there is guarded (`pcall`, an existence check,
or both) so a missing API degrades to "not available" rather than a load error.

---

## 5. Module contract

```lua
local ADDON, ns = ...

ns:RegisterModule("autorepair", {
    title    = "Auto Repair",                 -- shown in the list
    summary  = "Repairs at vendors.",         -- shown in the detail pane
    defaults = { useGuildFunds = false },     -- per-character settings

    reloadToEnable  = false,  -- true: turning ON applies after /reload
    reloadToDisable = false,  -- true: turning OFF applies after /reload
                              --   (e.g. it used hooksecurefunc, which cannot be undone)

    Available     = function(self) return true end,  -- optional: false, "reason"
    OnInitialize  = function(self) end,  -- self.db ready; build nothing
    OnEnable      = function(self) end,  -- start: events, hooks, frames
    OnDisable     = function(self) end,  -- stop: hide, unhook what can be unhooked
    BuildSettings = function(self, panel) end, -- optional; builds controls into `panel`
                                               -- once, the first time it is shown
    OnSettingChanged = function(self, key, value) end, -- optional
})
```

### 5.1 Services a module gets

- `self.db`: its per-character settings table, defaults filled in.
- `self:RegisterEvent(event, handler)`: bound only while enabled. Unknown events
  are skipped with a debug line instead of an error.
- `self:Safe(what, fn, ...)`: error containment under the module's name. After
  5 failures that context is switched off and reported once.
- `self:Schedule(key, delay, fn)`: coalesced deferred work.
- `self:Set(key, value)`: write a setting and fire `OnSettingChanged` if the
  module is running. Settings widgets use this.
- `self:Print(...)`, `self:Debug(...)`.

### 5.2 State model

Two booleans per module:

- **wanted**: what the user chose. Saved (`DyrutilitiesCharDB.modules[name].enabled`).
  Default `false`.
- **running**: whether `OnEnable` has run without a matching `OnDisable`. Not saved.

They differ only when a change is **pending a reload**. The window shows a
banner and a Reload button whenever any module is pending.

If `OnEnable` throws, the module is marked not running, its events are
unbound, and the error is reported. *wanted* stays as the user set it, so the
next login tries again.

### 5.3 Toggling

| Change | Module flag | Result |
|---|---|---|
| off → on | (none) | `OnEnable` now |
| off → on | `reloadToEnable` | saved; pending until reload |
| on → off | (none) | `OnDisable` now |
| on → off | `reloadToDisable` | saved; keeps running until reload |
| either | module unavailable | refused; the checkbox is disabled and shows the reason |

Flipping a pending change back before reloading clears the pending state.

### 5.4 Module directory and README (D-18)

Every module is a directory, `Modules/<Name>/`, where `<Name>` is the module's
PascalCase file name. The registered key stays lowercase, e.g.
`Modules/AutoRepair/AutoRepair.lua` registers `"autorepair"`. Each of its Lua
files is listed in the TOC. A loose `.lua` file directly in `Modules/` is not
allowed.

Each directory must contain a `README.md`, written from
`Documents/MODULE_README_TEMPLATE.md`, with two required top-level sections:

- **`## Functional`**: for the player. What the feature does, when it acts,
  how to use it, each setting and its default, and its known limits.
- **`## Technical`**: for the maintainer. Files, events and hooks,
  Blizzard APIs used (and which `Compat` accessors wrap them), secret-value
  exposure, reload flags and why, saved data shape, combat or taint concerns,
  and the probes and COMPAT_FINDINGS rows the feature rests on.

The README is updated in the same change as any change to the module's
behaviour or internals. `Tests/run_tests.py` fails when a module directory or
a TOC-listed module file lacks a README, or the README lacks either section.

---

## 6. The primary menu

### 6.1 Window

- A movable window named `DyrutilitiesMainWindow` (~560×380), dragged by its
  title bar and clamped to the screen. Its position is saved per character (D-4).
  Escape closes it (D-16).
- Title bar: "Dyrutilities" plus version, and a close button.
- **Left**: a scrolling list of every registered module in TOC order. Each
  row has a checkbox (wanted state) and the title. Clicking the row selects
  it. Clicking the checkbox toggles it. An unavailable module's checkbox is
  disabled and its title greyed.
- **Right**: the selected module's title, a status line (*On*, *Off*,
  *On after reload*, *Off after reload*, *Unavailable: reason*), its summary,
  then its settings panel (`BuildSettings`), or "This feature has no settings."
- **Bottom banner**, shown only while something is pending: "Some changes
  take effect after a reload." plus a **Reload UI** button.
- Empty state, before any module exists: "No features yet."
- The last selected module is remembered per character.

### 6.2 Opening it

| Route | Behaviour |
|---|---|
| `/dyru`, `/dyrutilities` | Toggle the window |
| Addon compartment | Click toggles the window; hover shows a tooltip. **Not visible on Forever** (D-8); registered but not advertised |
| Options › AddOns › Dyrutilities | A canvas page with one line of text and an **Open Dyrutilities** button, which closes the Settings panel and opens the window |

### 6.3 Slash subcommands

| Command | Does |
|---|---|
| `/dyru` | Toggle the window |
| `/dyru help` | List commands |
| `/dyru reset` | Move the window back to the centre |
| `/dyru compat` | What `Compat` detected on this client |
| `/dyru errors [reset]` | Errors recorded this session; `reset` re-arms anything switched off |
| `/dyru debug` | Toggle verbose logging |
| anything else | Prints help. It never falls through to a default action |

---

## 7. Saved variables

```lua
DyrutilitiesCharDB = {          -- SavedVariablesPerCharacter
    version   = 1,
    debug     = false,
    firstRun  = true,           -- cleared after the welcome line
    window    = { point = { "CENTER", "UIParent", "CENTER", 0, 0 }, selected = "autorepair" },
    modules   = {
        autorepair = {
            enabled  = false,   -- wanted state, §5.2
            settings = { useGuildFunds = false },
        },
    },
}
```

- Defaults are filled in explicitly, not through metatables, and shallow-copied
  so a default table is never shared with saved data.
- A module's entry is created the first time it registers, so adding a module
  needs no migration. Changing the shape of an existing stored value does: bump
  `version` and write a migration in `DB.lua`.
- A file stamped with a newer version than the code knows is left untouched,
  with one warning.
- `enabled` sits beside `settings`, not inside it, so a module setting can never
  collide with it.

---

## 8. Probes

`Dyrutilities_Probe` has no dependency on the addon, so it still runs when the
addon fails to load.

| Command | Answers |
|---|---|
| `/dyruprobe` | Build, TOC version, project IDs (every `WOW_PROJECT_*` global), the API paths the framework relies on, events, templates (each built with its proper frame type), secret-value functions. Saved to `DyrutilitiesProbeDB.survey` |
| `/dyruprobe settings` | Registers a throwaway canvas category, reports each call's result, then tries to open it |
| `/dyruprobe compartment` | Does `AddonCompartmentFrame` exist, and is Dyrutilities registered in it? |
| `/dyruprobe globals <pattern>` | Every global whose name matches a Lua pattern. Discovery for "does an API for X exist?" |
| `/dyruprobe ns <Namespace>` | Every member of a namespace table, e.g. `C_AddOns` |
| `/dyruprobe dump` | Re-print the last survey |

Every new feature that leans on an unverified API adds a probe subcommand
before the feature is written.

---

## 9. Tests

Headless suite in real Lua 5.1 (`lupa`) against a stubbed API. It covers:
bootstrap; every module defaulting to off; live enable/disable; the reload
flags and pending state; availability gating; `OnEnable` failure; per-character
defaults; the circuit breaker; slash routing, including that an unknown
subcommand does nothing but print help; the window's rows, checkbox, selection
and banner; the settings stub with and without the `Settings` API; and the
compartment function.

What it cannot cover: rendering, real taint/secret behaviour, and whether any
API actually exists on Forever. The probe covers those.

---

## 10. Open questions

1. D-13 to D-17 await confirmation.
2. Whether combat lockdown needs a per-module "no toggling in combat" flag.
   Nothing needs it until a feature touches protected frames.
3. The first features, and what each needs probed.
