#!/usr/bin/env python3
"""Run the repository checks, then Tests/tests.lua in a real Lua 5.1 interpreter.

1. Module layout (SPEC 5.4, D-18): every module is a directory under Modules/
   with a README.md that has both a "## Functional" and a "## Technical"
   section, and every module file the TOC lists lives in such a directory.
   This runs first and needs nothing installed; standard Lua cannot list a
   directory, so it lives here rather than in tests.lua.
2. The Lua suite. Lua 5.1 is what WoW runs, and the difference matters: 5.2
   changed `unpack`, `setfenv` and integer division, so a suite that passes
   under a newer Lua proves less than it looks.

Needs lupa for step 2, which bundles the interpreter:

    python -m venv venv && venv/Scripts/python -m pip install lupa
    python Tests/run_tests.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

TOC_NAME = "Dyrutilities.toc"
REQUIRED_SECTIONS = ("## Functional", "## Technical")
# Text that only exists in the unedited template: a README still carrying it
# was copied and never written.
TEMPLATE_MARKERS = ("Template for Modules/<Name>/README.md", "<One sentence:")


def toc_module_files(repo):
    """TOC lines that load something from Modules/, as forward-slash paths."""
    path = os.path.join(repo, TOC_NAME)
    if not os.path.isfile(path):
        return []
    files = []
    with open(path, "r", encoding="utf-8-sig") as handle:
        for line in handle:
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            entry = entry.replace("\\", "/")
            if entry.lower().startswith("modules/"):
                files.append(entry)
    return files


def check_module_layout(repo):
    """Return a list of problems with Modules/ and its READMEs (empty when sound)."""
    problems = []
    modules_root = os.path.join(repo, "Modules")
    module_dirs = set()

    for entry in toc_module_files(repo):
        parts = entry.split("/")
        if len(parts) < 3:
            problems.append("%s: TOC loads %s directly from Modules/; it must be in "
                            "Modules/<Name>/" % (TOC_NAME, entry))
            continue
        if not os.path.isfile(os.path.join(repo, *parts)):
            problems.append("%s: TOC lists %s, which does not exist" % (TOC_NAME, entry))
        module_dirs.add(parts[1])

    toc_dirs = set(module_dirs)
    if os.path.isdir(modules_root):
        for name in sorted(os.listdir(modules_root)):
            full = os.path.join(modules_root, name)
            if os.path.isdir(full):
                module_dirs.add(name)
                if name not in toc_dirs:
                    problems.append("Modules/%s/: no file in it is listed in %s, so the "
                                    "game never loads it" % (name, TOC_NAME))
            elif name.endswith(".lua"):
                problems.append("Modules/%s: a module must be a directory, "
                                "Modules/<Name>/, not a loose file" % name)

    for name in sorted(module_dirs):
        readme = os.path.join(modules_root, name, "README.md")
        if not os.path.isfile(readme):
            problems.append("Modules/%s/: missing README.md (copy "
                            "Documents/MODULE_README_TEMPLATE.md)" % name)
            continue
        with open(readme, "r", encoding="utf-8-sig") as handle:
            text = handle.read()
        for section in REQUIRED_SECTIONS:
            if not re.search(r"^%s\s*$" % re.escape(section), text, re.MULTILINE):
                problems.append("Modules/%s/README.md: missing the '%s' section"
                                % (name, section))
        for marker in TEMPLATE_MARKERS:
            if marker in text:
                problems.append("Modules/%s/README.md: still contains template text "
                                "(%r)" % (name, marker))
                break

    return problems


def run_layout_check():
    problems = check_module_layout(REPO)
    if problems:
        for problem in problems:
            print("  FAIL [module layout] " + problem)
    modules_root = os.path.join(REPO, "Modules")
    modules = [n for n in os.listdir(modules_root)
               if os.path.isdir(os.path.join(modules_root, n))] if os.path.isdir(modules_root) else []
    print("module layout: %d module(s), %d problem(s)" % (len(modules), len(problems)))
    return len(problems)


def run_lua_suite():
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        print("lupa is not installed. From the repo root:")
        print("    python -m venv venv && venv/Scripts/python -m pip install lupa")
        return None

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
    return failures


def main():
    layout_failures = run_layout_check()
    lua_failures = run_lua_suite()
    if lua_failures is None:
        return 2
    return 1 if (layout_failures or lua_failures) else 0


if __name__ == "__main__":
    sys.exit(main())
