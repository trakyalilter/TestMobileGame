#!/usr/bin/env python3
"""lint_gd.py — Godot-less static compile gate for the game scripts.

MUST run before every push (like audit_missions.py). Catches the GDScript
error classes that CI cannot: the release workflow's `--import || true` never
fails on compile errors and APK export packs broken scripts, so a single bad
line can ship a build that won't boot (this happened: `var st := stone`).

Checks:
  1. gdtoolkit `gdparse` parse errors, diffed against tools/gdparse_baseline.txt
     (known false positives — Godot accepts constructs gdtoolkit rejects, e.g.
     a lambda closed by a standalone `)` after a match block).
  2. Duplicate top-level func/const/var names per script (Godot-fatal,
     gdparse-invisible).
  3. `:=` inference-from-Variant heuristics (Godot-fatal, gdparse-invisible):
     RHS is an index access `x[...]`, a `.get(` call, or a bare identifier that
     is a for-loop variable over a non-int iterable (anything but `range(...)`
     or `X.size()`).

Exit 1 on any finding.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPTS = [
    os.path.join(ROOT, "scripts", "core", "game_state.gd"),
    os.path.join(ROOT, "scripts", "ui", "main.gd"),
    os.path.join(ROOT, "scripts", "core", "game_data.gd"),
]
BASELINE = os.path.join(HERE, "gdparse_baseline.txt")

errors = []

# ---------- 1. gdparse (baseline-diffed) ----------
def find_gdparse():
    """Return (cmd, extra_env). A --target pip install needs PYTHONPATH set."""
    from shutil import which
    if which("gdparse"):
        return ["gdparse"], {}
    # scratchpad --target install (session convention) or pip user install
    for cand in os.environ.get("GDTK_DIR", ""), "/tmp/gdtk":
        if cand and os.path.isfile(os.path.join(cand, "bin", "gdparse")):
            return [sys.executable, os.path.join(cand, "bin", "gdparse")], {"PYTHONPATH": cand}
    # try python module
    try:
        import gdtoolkit  # noqa
        return [sys.executable, "-m", "gdtoolkit.parser"], {}
    except ImportError:
        return None, {}

def gdparse_errors(cmd, extra_env, path):
    """Return normalized parse-error signatures for a script (may be empty)."""
    env = dict(os.environ)
    env.update(extra_env)
    p = subprocess.run(cmd + [path], capture_output=True, text=True, env=env)
    out = (p.stdout or "") + (p.stderr or "")
    sigs = []
    for m in re.finditer(r"Unexpected token Token\('(\w+)'.*?at line (\d+)", out):
        # signature = file + token type + the LINE CONTENT (line numbers drift)
        try:
            line = open(path).read().splitlines()[int(m.group(2)) - 1].strip()
        except Exception:
            line = "?"
        sigs.append("%s|%s|%s" % (os.path.basename(path), m.group(1), line))
    return sigs

cmd, extra_env = find_gdparse()
if cmd is None:
    print("WARN  gdtoolkit not available — parse check skipped "
          "(pip install --target /tmp/gdtk gdtoolkit, or set GDTK_DIR)")
else:
    baseline = set()
    if os.path.isfile(BASELINE):
        baseline = {l.strip() for l in open(BASELINE) if l.strip() and not l.startswith("#")}
    for path in SCRIPTS:
        for sig in gdparse_errors(cmd, extra_env, path):
            if sig not in baseline:
                errors.append("NEW parse error (vs baseline): %s" % sig)
    if "--write-baseline" in sys.argv:
        sigs = [s for p in SCRIPTS for s in gdparse_errors(cmd, extra_env, p)]
        with open(BASELINE, "w") as f:
            f.write("# gdparse false positives Godot accepts (signature: file|token|line-content).\n"
                    "# Regenerate ONLY after verifying new entries boot in Godot: lint_gd.py --write-baseline\n")
            f.write("".join(s + "\n" for s in sigs))
        print("baseline written: %d signature(s)" % len(sigs))
        sys.exit(0)

# ---------- 2. duplicate top-level names ----------
for path in SCRIPTS:
    seen = {}
    for i, l in enumerate(open(path).read().splitlines(), 1):
        m = re.match(r"(?:func|const|var) (\w+)", l)
        if m:
            name = m.group(1)
            if name in seen:
                errors.append("%s:%d duplicate top-level name '%s' (first at line %d)"
                              % (os.path.basename(path), i, name, seen[name]))
            else:
                seen[name] = i

def strip_noise(line):
    """Remove string literals and comments so identifier scans don't hit text."""
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
    return line.split("#")[0]

# ---------- 3. := inference-from-Variant heuristics ----------
SAFE_RHS = re.compile(
    r"""^(?:  \d | " | ' | \[ | \{ | \( | true\b | false\b | null\b
        | -?\d | Vector2 | Vector3 | Color\b | Callable\b | RegEx\b
        | int\( | float\( | str\( | String\( | bool\( | absf?\( | round\(
        | maxi\( | mini\( | maxf\( | minf\( | clampf\( | clampi\( | floor\( | pow\(
        | randi | randf | range\( | Time\. | PackedStringArray
        )""", re.X)

# Flag ONLY when the OUTERMOST RHS expression is Variant-typed. A Variant
# wrapped in a typing cast (`int(d.get(...))`, `String(arr[i])`) infers fine.
INDEX_RHS = re.compile(r"^\w+(\.\w+|\[[^\[\]]+\])*\[[^\[\]]+\]$")   # d[k], a.b[k], m[a][b]
GET_RHS = re.compile(r"^\w+(\.\w+)*\.get\(.*\)$")                    # d.get(k), a.b.get(k, v)

for path in SCRIPTS[:2]:  # game_data is generated consts only
    src = open(path).read().splitlines()
    for i, l in enumerate(src, 1):
        m = re.match(r"\s*var (\w+) := (.+)$", l)
        if not m:
            continue
        rhs = m.group(2).split("#")[0].strip()
        if SAFE_RHS.match(rhs):
            continue
        # outermost index access or .get( → Variant
        if INDEX_RHS.match(rhs) or GET_RHS.match(rhs):
            errors.append("%s:%d `var %s := %s` — RHS is Variant (index/.get); use a typed declaration"
                          % (os.path.basename(path), i, m.group(1), rhs))
            continue
        # RHS involving a for-loop variable over a non-int iterable (Variant):
        # a bare capture (`:= stone`) or an operator expression (`:= stone in
        # [...]`) both fail to infer. Scan back to the enclosing func for a
        # `for <ident> in ...:` at a shallower indent (a fixed window missed
        # the first shipped bug at 17 lines). A single call expression is safe
        # (typed by the callee's return), so only non-call RHS are checked.
        if re.match(r"^[\w.]+\(.*\)$", rhs):
            continue
        indent = len(l) - len(l.lstrip("\t "))
        # collapse call arguments first: a loop var inside a call (`float(w.get(x))`)
        # is typed by the callee's return and never breaks inference.
        top = strip_noise(rhs)
        while True:
            top2 = re.sub(r"[\w.]+\([^()]*\)", "0", top)
            if top2 == top:
                break
            top = top2
        for ident in set(re.findall(r"(?<![\w.\"'])([a-z_]\w*)\b", top)):
            if ident in ("in", "and", "or", "not", "if", "else", "true", "false", "null", "self"):
                continue
            for j in range(i - 2, -1, -1):
                if re.match(r"(?:static )?func ", src[j]):
                    break
                fm = re.match(r"([\t ]*)for %s in (.+):" % re.escape(ident), src[j])
                if fm and len(fm.group(1)) < indent:
                    it = fm.group(2).strip()
                    if not (re.match(r"^range\(", it) or it.endswith(".size()")
                            or re.match(r"^\d+$", it)):
                        errors.append("%s:%d `var %s := %s` — uses loop var '%s' over '%s' (Variant); use a typed declaration"
                                      % (os.path.basename(path), i, m.group(1), rhs, ident, it))
                    break

# ---------- 4. undefined local symbols (missing funcs / consts) ----------
# Would have caught the shipped "ported the call sites but not the engine"
# breakage: game_state.gd called _legal_affix_pool()/AFFIX_ZONE_CAP that were
# never added. Private `_name(` calls and bare ALL_CAPS identifiers are
# file-local in GDScript, so both must resolve within the same script.
GLOBAL_CAPS = re.compile(r"^(?:PI|TAU|INF|NAN|OK|FAILED|JSON|OS)$"
                         r"|^(?:ERR_|KEY_|MOUSE_|JOY_|SIDE_|CORNER_|MARGIN_|PRESET_"
                         r"|HORIZONTAL_|VERTICAL_|TEXTURE_|PROPERTY_|METHOD_"
                         r"|NOTIFICATION_|AUTOWRAP_|TYPE_|CONNECT_|PROCESS_|CURSOR_|FOCUS_)")
defs_by_file = {}
for path in SCRIPTS:
    src = open(path).read().splitlines()
    defs = set()
    for l in src:
        dm = re.match(r"\s*(?:static\s+)?(?:func|const|var|signal|enum|class)\s+(\w+)", l)
        if dm:
            defs.add(dm.group(1))
        em = re.match(r"\s*enum\s+\w*\s*\{(.*)\}", l)  # single-line enum members
        if em:
            defs.update(re.findall(r"(\w+)\s*[,=}]?", em.group(1)))
    defs_by_file[os.path.basename(path)] = defs
    for i, l in enumerate(src, 1):
        code = strip_noise(l)
        for name in re.findall(r"(?<![\w.])(_\w+)\s*\(", code):
            if name not in defs:
                errors.append("%s:%d call to undefined local function '%s()'"
                              % (os.path.basename(path), i, name))
        for name in re.findall(r"(?<![\w.])([A-Z][A-Z0-9_]+)\b(?!\s*\()", code):
            if name.lower() != name and name.upper() == name and name not in defs \
                    and not GLOBAL_CAPS.match(name):
                errors.append("%s:%d use of undefined constant '%s'"
                              % (os.path.basename(path), i, name))

# ---------- 5. cross-file autoload member resolution ----------
# main.gd's GameState.x / GameData.x must exist in the autoload script (the
# port once added UI for engine code that wasn't there).
OBJECT_MEMBERS = {"get", "set", "call", "call_deferred", "set_deferred", "connect",
                  "disconnect", "has_method", "has_signal", "emit_signal", "new",
                  "get_script", "notify_property_list_changed"}
for src_name, target in (("main.gd", "game_state.gd"), ("main.gd", "game_data.gd"),
                         ("game_state.gd", "game_data.gd")):
    auto = "GameState" if target == "game_state.gd" else "GameData"
    src_path = next(p for p in SCRIPTS if p.endswith(src_name))
    defs = defs_by_file[target]
    for i, l in enumerate(open(src_path).read().splitlines(), 1):
        for name in re.findall(r"\b%s\.(\w+)" % auto, strip_noise(l)):
            if name not in defs and name not in OBJECT_MEMBERS:
                errors.append("%s:%d %s.%s — not defined in %s"
                              % (src_name, i, auto, name, target))

# ---------- report ----------
for e in errors:
    print("ERROR " + e)
print("RESULT: %d errors" % len(errors))
sys.exit(1 if errors else 0)
