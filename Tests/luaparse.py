#!/usr/bin/env python3
"""Parse every .lua file with a real Lua 5.1 interpreter.

This is the strong check. `luacheck.py` beside it is a hand-written structural
checker that needs nothing installed; this one hands the file to the same
parser the game uses and is therefore right by construction -- it catches
precedence slips, bad escapes and malformed number literals that a bracket
counter cannot see.

It only PARSES. Nothing is executed, so a file that calls CreateFrame at load
time is fine here.

Needs lupa (which bundles the interpreter; nothing is installed system-wide):

    python -m venv venv && venv/Scripts/python -m pip install lupa

Usage: python Tests/luaparse.py [<path> ...]        (default: the repo root)
"""
import os
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    print("lupa is not installed; run Tests/luacheck.py instead, or:")
    print("    python -m venv venv && venv/Scripts/python -m pip install lupa")
    sys.exit(2)

SKIP_DIRS = {".git", "venv", ".venv", "__pycache__", ".claude"}


def lua_files(roots):
    for root in roots:
        if os.path.isfile(root):
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for name in sorted(filenames):
                if name.endswith(".lua"):
                    yield os.path.join(dirpath, name)


def main(argv):
    roots = argv[1:] or [os.path.dirname(os.path.dirname(os.path.abspath(__file__)))]
    lua = LuaRuntime(unpack_returned_tuples=False, register_eval=False)

    # Collapsed to a single return on the Lua side: nil for a clean parse, the
    # message otherwise. loadstring's own two returns come back across the
    # bridge as an object that is awkward to unpack, and the error text is the
    # only part worth having anyway.
    parse = lua.eval(
        "function(source, chunkname)"
        "  local chunk, err = loadstring(source, chunkname)"
        "  if chunk then return nil end"
        "  return err or 'unknown error'"
        "end"
    )

    checked = failed = 0
    for path in lua_files(roots):
        checked += 1
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
        err = parse(source, "@" + path)
        if err is not None:
            failed += 1
            print("FAIL %s\n     %s" % (path, err))

    print("%d file(s) parsed, %d failed" % (checked, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
