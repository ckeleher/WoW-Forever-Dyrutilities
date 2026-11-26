# Tests

A headless regression suite. It loads the addon into a real **Lua 5.1**
interpreter (what WoW runs) against a stubbed WoW Forever API, and exercises
the framework without a game client.

## Running

Needs Python 3 and [lupa](https://pypi.org/project/lupa/), which bundles a Lua
5.1 interpreter. Nothing is installed system-wide:

```bash
python -m venv venv && venv/Scripts/python -m pip install lupa
```

Then, from the repo root:

```bash
venv/Scripts/python Tests/luaparse.py     # real Lua 5.1 parse of every .lua file
venv/Scripts/python Tests/run_tests.py    # the suite
```

`python Tests/luacheck.py .` is a hand-written structural checker (block and
bracket balance, unterminated strings) that needs nothing installed.

## What is covered

There are no real features yet, so `tests.lua` registers **fixture modules**,
one per shape the framework must handle: plain live toggle, `reloadToDisable`,
`reloadToEnable`, unavailable, and an `OnEnable` that throws.

| Area | Asserts |
|---|---|
| Bootstrap | Namespaces exist; another addon's `ADDON_LOADED` is ignored; modules initialize at load |
| Defaults | Every module saved **off** and not started at login; defaults filled and table defaults copied, not aliased; `enabled` kept out of `settings` |
| Toggling | Live on/off; events bound only while running; both reload flags, the pending state, and flipping back clears it; a login starts wanted modules |
| Failure | An unavailable module is refused with its reason; an `OnEnable` that throws leaves the module stopped, not half-started |
| Storage | A new character starts clean; a non-table saved value is replaced; a newer file is warned about and its version left alone |
| Breaker | Switched off after the threshold, said once, reset re-arms it, returns survive, including a nil in the middle |
| Slash | `/dyru` toggles the menu; an unknown word prints help and does **not** open the menu; every subcommand runs |
| Window | A row per module; checkbox toggles; unavailable box disabled; selection remembered; settings panel built once, lazily; reload banner and its button; position saved and reset; Escape registration |
| Entry points | Compartment click/hover (including an unexpected argument shape); Options page registration, its Open button, and both fallbacks |
| Fallbacks | Checkbox, button and close button are hand-built when their template is missing |
| Empty state | A copy of the addon with no modules shows "No features yet" |
| Probe | Unknown subcommand doesn't run the survey; survey, settings, compartment, globals and ns probes run against the stub |

## What it cannot cover

Rendering, real taint and secret-value behaviour, and whether any API exists on
Forever at all. A green run means the logic is consistent, not that the addon
works. `Probe/Dyrutilities_Probe` answers the second question; see
`Documents/COMPAT_FINDINGS.md`.

## Adding a test

`tests.lua` is a list of `suite(name, fn)` calls, run in order. State carries
between suites on purpose, because it is one login. So a suite that cares about
a value must set it, not inherit it.

`wowstub.lua` is the fake world. `stub.fire(event, ...)` dispatches events,
`stub.runTimers()` flushes `C_Timer.After`, `frame:Click()` simulates a user
click (respecting disabled state, flipping a CheckButton first), and
`stub.templates` controls which templates `CreateFrame` accepts.
