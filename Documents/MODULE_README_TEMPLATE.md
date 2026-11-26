# <Title>

<!--
Template for Modules/<Name>/README.md (SPEC §5.4, D-18). Copy it into the
module's directory and replace every <placeholder>. Delete a subsection only
when it truly does not apply, and say so ("None.") rather than leaving it out
silently. The two top-level headings "## Functional" and "## Technical" are
required, and Tests/run_tests.py checks for them.
-->

<One sentence: what this feature does for the player.>

| | |
|---|---|
| Module key | `<key>` (as passed to `ns:RegisterModule`) |
| Default | Off |
| Status | <Planned / In development / Working / Broken on build NNNNN> |

## Functional

### What it does

<What changes in the game when this is on, in the player's terms. When it
acts, and when it deliberately doesn't.>

### How to use it

<Turn it on in /dyru. Then what: anything to click, type or watch for.
Any slash subcommands of its own.>

### Settings

| Setting | Default | Effect |
|---|---|---|
| <name> | <value> | <what it changes> |

<Or: "None.">

### Limits and known issues

<What it can't do, and why. Situations where it stays out of the way, such
as combat, instances or other addons.>

## Technical

### Files

| File | Role |
|---|---|
| `<Name>.lua` | <registration, lifecycle> |

### How it works

<The mechanism: which events it listens to, what it hooks (and whether
the hook can be undone), what frames it creates or modifies, and the order
things happen in.>

### Game APIs

| API | Wrapped by | Verified? |
|---|---|---|
| `<C_Something.Function>` | `Compat.<Accessor>` | <COMPAT_FINDINGS row, or "unverified: probe `/dyruprobe <sub>`"> |

### Secret values

<Which values it reads that are or may be secret (see COMPAT_FINDINGS,
"Secret values"), and how it behaves when one is. Or: "Reads no unit or
combat data.">

### Lifecycle and reload flags

<What OnEnable and OnDisable do. Why `reloadToEnable` / `reloadToDisable` are
set or not. Anything that cannot be undone without a reload.>

### Saved data

<The shape of `self.db` (its settings table) and anything else it stores.>

### Combat and taint

<Protected frames or functions it touches, and what it does under combat
lockdown. Or: "Touches nothing protected.">

### Probes and tests

<Probe subcommands this feature relies on, and the tests in Tests/tests.lua
that cover it.>
