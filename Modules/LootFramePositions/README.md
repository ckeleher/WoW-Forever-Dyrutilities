# Loot Frame Positions

Move the loot roll prompts and Blizzard's toasts (including the "you won" loot popup) from Edit Mode.

| | |
|---|---|
| Module key | `lootframepositions` |
| Default | Off |
| Status | Working: handles and toasts verified in game. Roll prompts presumed working, not yet seen in a real roll |

## Functional

### What it does

Gives you two blue handles that you drag in Edit Mode. One stands for the
group loot roll prompts (Need / Greed / Pass). The other stands for
Blizzard's toasts, including the "you won" loot popup. Once you have moved a
handle, the real frames appear where you left it.

Until you move a handle, nothing of Blizzard's is touched and everything
appears in its usual place.

### How to use it

1. Turn on **Loot Frame Positions** in `/dyru`.
2. Open Edit Mode (Esc > Edit Mode). A small **Dyrutilities** panel appears
   under Edit Mode's own window.
3. Tick **Loot Rolls** or **Alerts** in that panel. A blue handle appears.
4. Drag the handle where you want it. Its position is saved straight away.
5. Close Edit Mode. The handles go away.

To put everything back, click **Reset positions** in this feature's settings
in `/dyru`.

### Settings

| Setting | Default | Effect |
|---|---|---|
| Loot Rolls (Edit Mode panel) | Unticked | Shows the roll prompts' handle while Edit Mode is open |
| Alerts (Edit Mode panel) | Unticked | Shows the toasts' handle while Edit Mode is open |
| Reset positions (`/dyru`) | | Forgets both positions and returns both to Blizzard's defaults |

Positions are saved per character (SPEC F-1.4).

### Limits and known issues

- **The rolls' old slot stays reserved.** The prompts move, but Blizzard's
  bottom-of-screen stack still keeps room for them while a roll is up, so
  anything stacked above (such as the encounter bar) sits a little higher
  then, just as it does today (SPEC F-1.8).
- Several prompts stack **upward** from the bottom of the Loot Rolls handle,
  4 pixels apart.
- After **Reset positions** or turning the feature off mid-roll, prompts
  already on screen stay where they are until Blizzard next lays them out
  (the next roll added or removed). With no roll showing, nothing lingers.
- Until Blizzard's loot roll code exists, the Loot Rolls box is greyed out
  and says "(not available yet)". It is re-checked every time Edit Mode
  opens, so no reload is needed once the code appears.
- **Moving toasts moves every toast,** not only loot: achievements,
  reputation, garrison-style alerts and the rest. They all share one anchor
  (SPEC F-1.2).
- Toasts stack **upward** from the bottom of the Alerts handle.
- Positions are saved relative to the centre of the screen. A large change
  of resolution or UI scale can push a handle near the edge; it is clamped
  to the screen.

## Technical

### Files

| File | Role |
|---|---|
| `LootFramePositions.lua` | Registration, the two anchors and their handles, the Edit Mode panel, the settings pane |

### How it works

The module owns two frames of its own: `DyrutilitiesAlertAnchor` (300×10)
and `DyrutilitiesLootRollAnchor` (277×67, one roll prompt). Each carries a
handle: a blue box at FULLSCREEN_DIALOG strata, shown only while Edit Mode
is open and its checkbox is ticked. Dragging a handle moves its anchor with
`StartMoving`. On drop, the anchor's centre is saved as an offset from
UIParent's centre, the same scheme as the menu window, and then applied.

**Applying a kind:**

- **With a saved point:** the anchor is placed there and Compat is told to
  attach Blizzard's frames to it. For toasts that is
  `AlertFrame:SetBaseAnchorFrame(anchor)`.
- **Without one:** the anchor is placed where Blizzard's frames are by
  default (for toasts, `AlertFrame`'s BOTTOM). If we had attached them, they
  are detached with `ResetBaseAnchorFrame()`.

So an unmoved kind never touches Blizzard's frames.

**Edit Mode** has no addon registration route (COMPAT_FINDINGS, "Edit Mode").
The module listens through `Compat.OnEditMode`, which uses the
`EditMode.Enter` / `EditMode.Exit` EventRegistry callbacks. On enter, the
panel `DyrutilitiesEditModePanel` is anchored below `EditModeManagerFrame`
and shown with the ticked handles. On exit, both are hidden. The callbacks
are registered once and check `running`, so a stopped module ignores them.

**Roll prompts.** `GroupLootContainer` is a managed frame in Blizzard's
bottom stack, which re-anchors it on every relayout (measured), so it is
never moved. Instead `Compat.SetLootRollAnchor(anchor)` installs, once, a
`hooksecurefunc` post-hook on `GroupLootContainer_Update` and an `OnShow`
`HookScript` on each of `GroupLootFrame1`–`4`. After Blizzard lays the
prompts out, the hook re-anchors every shown prompt to our anchor's BOTTOM,
stacked upward (height + 4). The order is the container's `rollFrames`
where present, otherwise `GroupLootFrame1`–`4`. The hooks can't be removed,
so `ResetLootRollAnchor` clears the anchor they read and they go inert.
Nothing anchors to the container (measured), so no other frame is affected.
The default handle position is the container's slot: TOP of
`BottomManagedFrameContainer`.

Blizzard's loot roll code exists before this addon loads (measured), but a
patch could change that. So
`Compat.LootRollAnchorAvailable()` checks for it each time it's asked, and
never caches a "no". A saved roll position applied at login before the code
exists is kept by Compat. It is hooked up on the first `ADDON_LOADED` or
`PLAYER_ENTERING_WORLD` after the code appears.

### Game APIs

| API | Wrapped by | Verified? |
|---|---|---|
| `EventRegistry` `EditMode.Enter` / `EditMode.Exit` | `Compat.OnEditMode` | Yes: COMPAT_FINDINGS "Edit Mode" |
| `EditModeManagerFrame:IsShown`, as an anchor target | `Compat.IsEditModeActive`, `Compat.AnchorBelowEditMode` | Present and not protected. Placement of the panel below it: not yet seen in game |
| `AlertFrame:SetBaseAnchorFrame` / `ResetBaseAnchorFrame` | `Compat.SetAlertBaseAnchor` / `ResetAlertBaseAnchor` | Yes: COMPAT_FINDINGS "Loot roll and alert frames", 26 Nov 2026 |
| `AlertFrame` as an anchor target | `Compat.AnchorAtAlertFrame` | Position measured (BOTTOM, 0, 128) |
| `GroupLootContainer_Update` post-hook, `GroupLootFrame1`–`4` `SetPoint` | `Compat.SetLootRollAnchor` / `ResetLootRollAnchor` | Container re-anchored by the stack, nothing anchored to it: measured (`managed`, `simulate`). **The hook during a real roll: unverified** (`/dyruprobe lootframes watch`, or just try it) |
| A frame at FULLSCREEN_DIALOG over Edit Mode | | Yes: shown and draggable (26 Nov 2026) |

### Secret values

Reads no unit or combat data. It reads only frame positions of its own
frames.

### Lifecycle and reload flags

- **OnEnable** builds the anchors and panel once, applies each saved point,
  and hooks Edit Mode once. If Edit Mode is already open, it shows the panel.
- **OnDisable** detaches anything it attached (`ResetBaseAnchorFrame`), so
  toasts return to their default place at once, and hides the panel and
  handles.

Neither reload flag is set. The toast change undoes exactly, and the roll
hooks go inert once their anchor is cleared, so Blizzard's next layout of
the prompts stands.

### Saved data

`self.db` (per character, `DyrutilitiesCharDB.modules.lootframepositions.settings`):

| Key | Shape | Meaning |
|---|---|---|
| `alertPoint` | `{ "CENTER", "UIParent", "CENTER", x, y }` or nil | The toasts' anchor; nil = Blizzard's default |
| `rollPoint` | same | The roll prompts' anchor |
| `showAlertHandle` | boolean, default false | The Alerts checkbox in the Edit Mode panel |
| `showRollHandle` | boolean, default false | The Loot Rolls checkbox |

### Combat and taint

Touches nothing protected. `AlertFrame` and the loot frames are not
protected (COMPAT_FINDINGS), and `SetBaseAnchorFrame` is called with our
own frame. The roll hook re-anchors only the prompts, never the managed
container or its stack, which also holds frames that may be protected. No blocked actions were recorded by the probe's listener while
the same calls ran.

### Probes and tests

- `/dyruprobe lootframes` (survey, `move`, `alertanchor`): the basis for the
  toasts.
- `/dyruprobe lootframes managed`, `simulate`: the basis for the roll
  prompts' strategy. `watch` records where real prompts land. `timing`
  records when Blizzard's loot roll code appears during a load.
- `/dyruprobe editmode` (and `watch`): the Edit Mode callbacks and the
  overlay.
- `Tests/tests.lua`, suite "module: loot frame positions": defaults,
  availability, Edit Mode show/hide, dragging and saving, applying and
  resetting the toast anchor, prompts following our anchor through
  Blizzard's relayout and stacking, the container never moved, disable, and
  Reset positions. Suite "…, Blizzard's loot code loading late": the box
  appears without a reload, and a saved position is hooked up when the code
  loads.
