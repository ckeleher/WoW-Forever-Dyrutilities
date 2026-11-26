# Compatibility findings

What has actually been **measured** on the WoW Forever client, as opposed to
what the code assumes. Kept current: after every patch, re-run the probe and
update this file.

**Status:** first survey taken 25 November 2026 (build `71139`). Every
framework assumption that the probe can check by calling the API held, and
the on-screen checks passed. The one exception: Forever's minimap shows no
addon-compartment button, so that route to the menu does not exist in practice.

## How to re-run

1. `.\Tools\sync.ps1` installs both `Dyrutilities` and `Dyrutilities_Probe`.
2. Log in on Forever and run:

   ```
   /dyruprobe
   /dyruprobe settings
   /dyruprobe compartment
   ```

   `/reload` first if the probe changed since you logged in. The probe's Lua
   is loaded at login, so a new subcommand isn't recognised until then.
3. `/reload` again to write the results to
   `WTF\Account\<account>\SavedVariables\Dyrutilities_Probe.lua`, then
   update the tables below. Where a finding contradicts `SPEC.md`, amend the
   spec.

---

## Client identification

| | Expected | Observed (25 Nov 2026) |
|---|---|---|
| `GetBuildInfo()` version | `1.60.1` | `1.60.1` |
| build / date | | `71139`, `Nov 24 2026` |
| TOC version | `16001` | `16001`, returned as a **number**, not a string |
| `WOW_PROJECT_ID` | unknown | `18` |
| `WOW_PROJECT_*` constants | unknown | `MAINLINE = 1`, `CLASSIC = 2`, `CAMELOT = 18`. **There is no `WOW_PROJECT_FOREVER`.** The client identifies itself as Camelot, Forever's internal name |
| Locale | | `enUS` |

## Framework assumptions

| Question | Assumed | Observed (25 Nov 2026) | Used by |
|---|---|---|---|
| `C_EventUtils.IsEventValid` | Present | **Present** | `Compat.HasEvent` |
| `C_AddOns.GetAddOnMetadata` | Present | **Present**. The bare global `GetAddOnMetadata` is **absent** | version string. Compat's fallback to the global is dead code, and harmless |
| `C_Timer.After` | Present | **Present** | `Module:Schedule`, first-run message |
| `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory` | Present | **Present; both calls succeed** (probe page got category id `54`, a number) | `UI/SettingsStub.lua` |
| `Settings.OpenToCategory(id)` | Present | **Present, and it opens the panel on the given page** (seen 25 Nov 2026) | not used by the addon |
| `InterfaceOptions_AddCategory` / `InterfaceOptionsFrame` | Fallback only | **Both absent.** The legacy route is dead code, and harmless | Compat fallback |
| `SettingsPanel` + `HideUIPanel` | Present | **Both present. Our page is listed under AddOns, and "Open Dyrutilities" closes the panel and opens the window** (seen 25 Nov 2026) | Options page button |
| `## AddonCompartmentFunc` registers us | Yes | **Yes**: Dyrutilities appears in `AddonCompartmentFrame.registeredAddons`, and the TOC function reads back correctly. `AddonCompartmentFrame.RegisterAddon` also exists | compartment entry |
| The compartment's dropdown button is visible on Forever's reskinned minimap | Yes | **NO. There is no compartment button on screen** (looked for, 25 Nov 2026), although `AddonCompartmentFrame` exists and we are registered in it. The registration stays, invisible and harmless, in case a patch or another addon ever shows the button | compartment entry (SPEC D-8, amended) |
| Compartment hover passes the menu button as arg 2 | Probably | **Untestable** while the button is not shown | tooltip |
| `UISpecialFrames` | Present | **Present, and Escape closes the window** (seen 25 Nov 2026) | Escape-to-close |
| The window opens via `/dyru` and shows the empty state | Yes | **Yes**, with no Lua errors seen on first load (25 Nov 2026) | menu |
| `ReloadUI` | Present | **Present**, and so is `C_UI.Reload` | reload banner |
| `hooksecurefunc`, `StaticPopup_Show`, `MenuUtil.CreateContextMenu` | Present | **All present** | future features |
| Events: `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_*`, `ADDON_ACTION_*` | Present | **All present** | bootstrap; future |

### Templates

All 14 surveyed templates build without error, so **none of the hand-built
fallbacks in `Core/Widgets.lua` is in use.** This also informs SPEC D-13: a
Blizzard-styled window is fully available.

`UIPanelButtonTemplate`, `UIPanelCloseButton`, `UICheckButtonTemplate`,
`InterfaceOptionsCheckButtonTemplate`, `BackdropTemplate`,
`BasicFrameTemplateWithInset`, `PortraitFrameTemplate`, `ButtonFrameTemplate`,
`UIPanelScrollFrameTemplate`, `ScrollFrameTemplate`, `OptionsSliderTemplate`,
`MinimalSliderTemplate`, `InputBoxTemplate`, `SecureActionButtonTemplate`.

## Secret values. This one matters for every future feature

| Question | Observed (25 Nov 2026) |
|---|---|
| `issecretvalue`, `canaccessvalue`, `issecrettable` | **All present** |
| `C_Secrets` namespace | **Present** (a table). Members not yet listed: `/dyruprobe ns C_Secrets` |
| `issecretvalue(1)` | `false`, so the function answers sanely |
| `UnitHealth("player")` is secret **out of combat** | **TRUE** |

**The player's own health is a secret value even outside combat.** Forever
is stricter than "combat-gated" here. Any feature that reads unit data
(health, power, probably auras and more) must be designed around secrets from
the start, and each value it needs must be probed in and out of combat before
the feature is written. Not yet measured: whether this applies to all units,
to power, or in instances only.

## Seen on disk after first login

`DyrutilitiesCharDB` was created per character
(`WTF\Account\<account>\<realm id>\<character>\SavedVariables\Dyrutilities.lua`)
with `version = 1`, `firstRun = false`, and empty `modules` and `window`. That
matches SPEC §7. The welcome line ran.
