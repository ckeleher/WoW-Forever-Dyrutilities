# Dyrutilities

A collection of small utility and quality-of-life features for **WoW Forever**
(1.60.1). Each feature is an independent submodule with its own settings,
switched on from one window. **Every feature starts off.**

No libraries. No features yet: v0.1 is the framework and the menu.

## Install (development)

```powershell
.\Tools\sync.ps1            # copy Dyrutilities + Dyrutilities_Probe into _forever_\Interface\AddOns
.\Tools\sync.ps1 -Watch     # ...and re-copy on every change
.\Tools\sync.ps1 -Link      # junction the repo in instead of copying
```

Restart the client after a first install or a `.toc` change. Otherwise
`/reload` is enough.

## Using it

| Route | |
|---|---|
| `/dyru` or `/dyrutilities` | Open or close the menu |
| Esc › Options › AddOns › Dyrutilities | Button that opens the menu |

There is no minimap icon. The addon registers with Blizzard's addon
compartment, but Forever's minimap doesn't show that button.

`/dyru help` lists the rest: `reset`, `compat`, `errors [reset]`, `debug`.

## Probing the client

`Dyrutilities_Probe` is a separate addon that checks every API assumption on
the live client. It is not part of a release.

```
/dyruprobe                  survey
/dyruprobe settings         Options panel registration
/dyruprobe compartment      addon compartment
/dyruprobe globals <pat>    find globals by Lua pattern
/dyruprobe ns <Name>        list a namespace's members
```

Record results in `Documents/COMPAT_FINDINGS.md`.

## Documents

- `Documents/SPEC.md`: design, decision log, module contract
- `Documents/COMPAT_FINDINGS.md`: what has been measured on the client
- `Tests/README.md`: the headless test suite
