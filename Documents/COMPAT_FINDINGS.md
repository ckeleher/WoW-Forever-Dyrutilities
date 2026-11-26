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

## Loot roll and alert frames (feature F-1, 26 Nov 2026)

From `/dyruprobe lootframes` and `/dyruprobe lootframes move`, out of combat,
no loot roll in progress. **No blocked actions were recorded.**

| Frame | Type | Protected | Parent | Anchor (idle) | Layout |
|---|---|---|---|---|---|
| `GroupLootContainer` | Button | **no** | UIParent | none while hidden | **Managed**: `isManagedFrame = true`, `layoutParent = BottomManagedFrameContainer`, `layoutIndex = 3`. Blizzard's bottom-of-screen stack positions it |
| `GroupLootFrame1`–`4` | Frame, 277×67, DIALOG strata | no | UIParent | none while hidden | not managed; the container anchors them |
| `AlertFrame` | Frame, 10×10 | **no** | UIParent | `BOTTOM` of UIParent, (0, 128) | **not managed** |
| `BonusRollFrame` | Frame | no | UIParent | none while hidden | not managed |
| `LootFrame` (personal loot window) | Frame | no | UIParent | `TOPLEFT` (16, −116) | **Edit Mode system 10**. Edit Mode already moves it |

Move test (each frame re-anchored to UIParent centre for 10 s, then restored):

| | `GroupLootContainer` | `AlertFrame` |
|---|---|---|
| `SetPoint` from addon code | ok | ok |
| Still there after 1 s | held | held |
| After `AlertFrame:UpdateAnchors()` | held | held |
| A preview toast (`LootAlertSystem:AddAlert`) | | **appeared at the moved position** (seen by eye) |

**Not conclusive for the roll container:** it was hidden throughout, and
`UIParent_ManageFramePositions` does not exist on this client, so nothing
asked the managed stack to lay it out again. What happens when a real roll
shows it is still unmeasured.

Other findings:

- `AlertFrame` has `SetBaseAnchorFrame`, `ResetBaseAnchorFrame`,
  `AddAutoAnchoredSubSystem`, `AddExternallyAnchoredSubSystem`,
  `SetSubSystemAnchorPriority`, `CleanAnchorPriorities` and `UpdateAnchors`.
- **`AlertFrame:SetBaseAnchorFrame(ourFrame)` works** (`/dyruprobe lootframes
  alertanchor`, 26 Nov 2026). Both calls succeed, and a preview toast appeared beside
  our frame (seen by eye). **`ResetBaseAnchorFrame()` works too**: the next
  toast appeared back in the usual place. Toasts can follow a frame of ours
  without moving Blizzard's, and the change undoes cleanly without a reload.
- **The bottom stack takes the roll container back** (`/dyruprobe lootframes
  managed` and `simulate`, 26 Nov 2026):

  | | Observed |
  |---|---|
  | `BottomManagedFrameContainer` | `BOTTOM` of UIParent, (0, 35). Keeps its frames in `showingFrames` |
  | Showing in it while idle | only `EncounterBar` (#6), at `TOP` of the stack |
  | Anchored to `GroupLootContainer` | **nothing**, idle or shown |
  | Container shown as a roll would | the stack puts it at `TOP -> BottomManagedFrameContainer:TOP (0, 0)` |
  | Moved while shown, then the stack's `Layout()` | **re-anchored** to the stack's TOP again |

  So moving `GroupLootContainer` itself does not stick: the next relayout
  undoes it. Nothing else leans on the container, so re-anchoring the roll
  frames inside it disturbs no other frame. The stack has `RemoveManagedFrame`,
  `IgnoreLayoutIndex` and `MarkIgnoreInLayout` methods (ways to take the
  container out of the stack); none has been tried.
- **Still unmeasured:** how `GroupLootFrame1`–`4` are anchored inside the
  container during a real roll. `watch` has not seen one yet.
- **Blizzard's loot roll code is present before Dyrutilities loads**
  (`/dyruprobe lootframes timing`, 26 Nov 2026). `GroupLootContainer_Update`,
  `GroupLootContainer` and `GroupLootFrame1` were all present at our load,
  and at every `ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`
  after it. So the "Loot Rolls (not available yet)" seen earlier that day
  was **not** load order. The cause is unexplained; most likely that session
  was still running code from before the roll strategy was synced. The
  on-demand check added for it is kept, because it is harmless.
  After a `/reload`, Loot Rolls is offered in the Edit Mode panel and can be
  ticked (seen 26 Nov 2026).
- **Not yet seen: the prompts following our anchor in a real roll.** It is
  presumed to work for now (user's call, 26 Nov 2026). Confirm at the first
  group roll with `/dyruprobe lootframes watch`, then `/reload`.
- `GroupLootContainer_*` functions exist, including `_Update`, `_AddFrame`
  and `_RemoveFrame`. Rolls are laid out by plain global functions, which
  `hooksecurefunc` can follow.
- `LootAlertSystem`, `LootUpgradeAlertSystem` and `MoneyWonAlertSystem` exist
  among 31 `*AlertSystem` globals.

## Edit Mode (26 Nov 2026)

| Question | Observed |
|---|---|
| `EditModeManagerFrame` | present, not protected |
| `EventRegistry` callbacks `EditMode.Enter` / `EditMode.Exit` | **both fire** |
| `hooksecurefunc` on `EnterEditMode` / `ExitEditMode`, `OnShow` / `OnHide` hooks | **all fire** |
| An addon frame shown on Edit Mode enter, at FULLSCREEN_DIALOG strata | **visible over Edit Mode** (seen by eye), **and draggable**: both module handles drag and keep their position (seen 26 Nov 2026) |
| `Enum.EditModeSystem` | 31 systems. The only loot one is `LootFrame = 10`, the personal loot window. **There is no native system for roll prompts or alerts** |
| Registration API | `EditModeManagerFrame:RegisterSystemFrame` exists, but it takes an `Enum.EditModeSystem` value with Blizzard-defined settings. There is no addon-facing route |
| `C_EditMode` | layout load/save/convert and account settings only |
| `AccountSettings` panel (the "show" checkboxes) | present |

## Seen on disk after first login

`DyrutilitiesCharDB` was created per character
(`WTF\Account\<account>\<realm id>\<character>\SavedVariables\Dyrutilities.lua`)
with `version = 1`, `firstRun = false`, and empty `modules` and `window`. That
matches SPEC §7. The welcome line ran.
