#!/usr/bin/python3 -I
# Stand-in for a Lead Architect crew member: claude -p stream-json. Each role runs the crew CLI the way the agent's Bash
# tool would, driven by what the relay delivers to it. Everything it does is logged to fake.log as one JSON object per line.
import sys, json, os, subprocess, re, shlex
args = sys.argv[1:]
role = os.environ.get("XFINDER_CREW_ROLE", "?")
branch = os.environ.get("XFINDER_CREW_BRANCH")
here = os.path.dirname(os.path.abspath(sys.argv[0]))
log = open(os.path.join(here, "fake.log"), "a")
def L(**kw):
    kw["role"] = role
    log.write(json.dumps(kw, ensure_ascii=False) + "\n"); log.flush()
def arg(name):
    return args[args.index(name)+1] if name in args else None
settings = arg("--settings")
parsed = None
if settings and os.path.exists(settings):
    parsed = json.load(open(settings))
L(start=True, cwd=os.path.realpath(os.getcwd()), root=os.environ.get("XFINDER_CREW_ROOT"), branch=branch,
  mode=arg("--permission-mode"), disallowed=arg("--disallowedTools"),
  ask_rules=len((parsed or {}).get("permissions", {}).get("ask", [])),
  guard=(((parsed or {}).get("hooks", {}).get("PreToolUse") or [{}])[0].get("hooks") or [{}])[0].get("command"),
  matcher=((parsed or {}).get("hooks", {}).get("PreToolUse") or [{}])[0].get("matcher"),
  system_has_branch=bool(branch) and branch in (arg("--append-system-prompt") or ""),
  system_ascii=all(ord(c) < 128 for c in (arg("--append-system-prompt") or "")))
def crew(*a):
    r = subprocess.run(["xfinder-crew", *a], capture_output=True, text=True)
    L(cli=list(a), exit=r.returncode, err=r.stderr.strip()[:200])
    return r
def git(*a):
    return subprocess.run(["git", "-c", "user.name=fake", "-c", "user.email=fake@x", *a], capture_output=True, text=True)
def branches_from_who():
    out = crew("who").stdout if False else subprocess.run(["xfinder-crew", "who"], capture_output=True, text=True).stdout
    found = {}
    for line in out.splitlines():
        name = line.split(" ")[0]
        if "(branch: " in line:
            found[name] = line.split("(branch: ")[1].rstrip(")")
    return found
def out(o): print(json.dumps(o), flush=True)
for line in sys.stdin:
    text = json.loads(line)["message"]["content"]
    L(got=text[:400])
    reply = "ok"
    if role == "lead":
        if "GOAL_PLAN" in text:
            b = branches_from_who()
            crew("send", "frontend", "--task", "Build the share button", "--criteria", "tests green, no schema change")
            crew("send", "backend", "--task", "Add the share API", "--criteria", "tests green")
            crew("send", "frontend", "just a plain question")                      # refused: a builder is handed TASK + CRITERIA
            crew("merge", "--branch", b.get("backend", "crew/none-backend"))       # refused: nothing done yet
            reply = "planned"
        elif "approved by both security and reviewer" in text:
            br = [w for w in text.split() if w.startswith("crew/")][0]
            crew("merge", "--branch", br)
            reply = "merging " + br
    elif role in ("frontend", "backend"):
        if "TASK:" in text and "[FROM: lead]" in text:
            guard_cmd = (((parsed or {}).get("hooks", {}).get("PreToolUse") or [{}])[0].get("hooks") or [{}])[0].get("command")
            if guard_cmd and os.path.exists(shlex.split(guard_cmd)[0]):
                cwd = os.path.realpath(os.getcwd())
                def probe(tool, inp):
                    r = subprocess.run(["sh", "-c", guard_cmd], input=json.dumps({"tool_name": tool, "tool_input": inp, "cwd": cwd}), capture_output=True, text=True)
                    try: return (json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"] if r.stdout.strip() else "none")
                    except Exception: return "bad:" + r.stdout[:80]
                L(guard_probe=True, outside_write=probe("Write", {"file_path": os.path.join(cwd, "..", "..", "outside.txt")}),
                  inside_write=probe("Write", {"file_path": os.path.join(cwd, "inside.txt")}),
                  push=probe("Bash", {"command": "git -C . push origin main"}),
                  shell_write_outside=probe("Bash", {"command": "echo x > ../../outside2.txt"}),
                  nested_push=probe("Bash", {"command": "bash -c 'git push'"}),
                  plain_ls=probe("Bash", {"command": "ls -la"}))
            with open(role + ".txt", "w") as f: f.write("work of " + role + "\n")
            git("add", role + ".txt"); git("commit", "-q", "-m", "work of " + role)
            if role == "backend":
                with open("scratch-uncommitted.txt", "w") as f: f.write("never committed\n")
            crew("done", "--branch", branch, "--tests", "ran 3 tests: all passed")
            if role == "frontend":
                # a builder trying to approve someone else's branch
                b = branches_from_who()
                # --round so the CLI lets it through: the RELAY's rule (judges only) is what this probes, not the CLI's syntax check
                crew("verdict", "approved", "--branch", b.get("backend", "crew/none-backend"), "--round", "1", "--note", "looks fine")
            reply = "done " + role
    elif role in ("security", "reviewer"):
        if "JUDGE REQUEST for branch" in text:
            br = text.split("JUDGE REQUEST for branch ")[1].split(",")[0].split(" ")[0]
            m = re.search(r"review round (\d+)", text)
            rnd = m.group(1) if m else "1"
            if role == "security" and br.endswith("-backend"):
                crew("verdict", "rejected", "--branch", br, "--round", rnd, "--note", "src/api.py:12 builds a shell command from input")
            else:
                crew("verdict", "approved", "--branch", br, "--round", rnd, "--note", "ok")
            reply = "judged " + br
    out({"type": "assistant", "parent_tool_use_id": None, "message": {"content": [{"type": "text", "text": reply}]}})
    out({"type": "result", "subtype": "success", "is_error": False, "result": reply, "total_cost_usd": 0.01})
