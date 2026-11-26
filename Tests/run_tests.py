#!/usr/bin/env python3
"""Run Tests/tests.lua in a real Lua 5.1 interpreter.

Lua 5.1 is what WoW runs, and the difference matters: 5.2 changed `unpack`,
`setfenv` and integer division, so a suite that passes under a newer Lua proves
less than it looks.

Needs lupa, which bundles the interpreter:

    python -m venv venv && venv/Scripts/python -m pip install lupa
    python Tests/run_tests.py
"""
import os
import sys

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    print("lupa is not installed. From the repo root:")
    print("    python -m venv venv && venv/Scripts/python -m pip install lupa")
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def main():
    lua = LuaRuntime(unpack_returned_tuples=False, register_eval=False)
    lua.globals().REPO_ROOT = REPO.replace("\\", "/")

    with open(os.path.join(HERE, "tests.lua"), "r", encoding="utf-8") as handle:
        source = handle.read()

    chunk = lua.eval("function(src) return loadstring(src, '@Tests/tests.lua') end")(source)
    if chunk is None:
        print("tests.lua does not parse")
        return 1

    chunk()

    failures = lua.globals().RESULT_FAILURES
    if failures is None:
        print("the suite did not finish")
        return 1
    return 1 if failures > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
