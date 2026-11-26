# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Dyrutilities: a World of Warcraft addon for the **WoW Forever** client
(1.60.1, Interface `16001`). It is a collection of small, independent
utility/QoL features, each a submodule, toggled from one menu window. Every
feature defaults to **off**. `Documents/SPEC.md` is the source of truth for
design; `Documents/COMPAT_FINDINGS.md` records what has actually been measured
on the client.

WoW Forever is **Mainline-family** code (Midnight 12.1.x UI and API, with
secret values active), not Classic. Knowledge from the sibling Classic addons
(DyrueWoWTools, DyrueUnitFrames) about *what the API does* does not transfer;
their *structure* does.

## Git and GitHub

- Claude Code may commit, push branches, and open pull requests **when the user
  asks**. Never commit directly to `main`; branch first.
- Commit messages end with the `Co-Authored-By` trailer and PR descriptions end
  with the "Generated with Claude Code" line, as Claude Code's attribution
  guidance gives them.
- Read-only and sync commands (`git status`, `git diff`, `git log`,
  `git fetch`, `git pull`) are always fine.

## How decisions get made

- **Do not make design assumptions.** Work through each decision with the user
  and record the outcome in the SPEC's decision log. A choice Claude had to make
  to keep moving goes in the log marked as Claude's default, to be confirmed.
- **When unsure whether the game API supports something, build a probe**, not
  a guess. Probes live in `Probe/Dyrutilities_Probe` (`/dyruprobe`), never in
  the shipped addon. Results go into `COMPAT_FINDINGS.md`. Where a finding
  contradicts the SPEC, amend the SPEC.

## Code rules

- No libraries. Plain frames, plain SavedVariables.
- `Core/Compat.lua` is the only file that calls a version-sensitive API or
  touches a Blizzard-owned frame/global. Feature-probe, never version-check.
- Each feature is one file in `Modules/`, registered with `ns:RegisterModule`
  (contract in SPEC §5) and listed in the TOC. Nothing central needs editing to
  add one.
- `pcall`, never `xpcall` with arguments (Lua 5.1 drops them).
- An unrecognised slash subcommand prints help; it never falls through to a
  default action.

## Checks

```bash
python Tests/luaparse.py      # real Lua 5.1 parse of every file
python Tests/run_tests.py     # headless suite against Tests/wowstub.lua
```

Both need `lupa` (see `Tests/README.md`). `python Tests/luacheck.py .` is the
no-dependency structural fallback. Run them after every change.
