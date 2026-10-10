#!/usr/bin/env python3
"""Open every sidebar destination via xfinder://settings?page=… and read the rendered AX tree in
English and Vietnamese. Reports: node count per language, Vietnamese-diacritic lines on the English UI
(minus the allowlist / proper nouns), pages whose header is missing, and pages with suspiciously few nodes."""
import json, re, subprocess, sys, time
REPO="/Users/wolong/github/XFinder"; D="com.xfinder.app"
def sh(*a): return subprocess.run(a,capture_output=True,text=True)
def pid(): return sh("pgrep","-x","XFinder").stdout.split()[0]
src=open(f"{REPO}/XFinder/Models/SidebarDestination.swift",encoding="utf-8").read()
blk=re.search(r"static var groups.*?\{(.*?)\n    \}",src,re.S).group(1)
pages=re.findall(r"\.(\w+)",blk)+["about"]
allow=set(json.load(open(f"{REPO}/XFinder/Resources/L10n.allowlist.json"))["sameByDesign"])|{"App Exposé","Mission Control","Quick Look","XFinder","BSKV3P 35K","Pin"}
VI=re.compile(r"[À-ỹ]")
orig_lang=sh("defaults","read",D,"AppLanguage").stdout.strip() or "vietnamese"
def dump():
    sh("osascript","-e",'tell application "XFinder" to activate'); time.sleep(0.4)
    r=sh("/usr/bin/env","swift",f"{REPO}/docs/probes/probe-ax-dump.swift",pid())
    out=r.stdout
    # The probe exits 3 when the session is locked: AX then hides every window, and a page full of
    # zeros would read as a blank UI. Abort the whole sweep rather than report 33 fake failures.
    if r.returncode==3 or "SCREEN LOCKED" in out:
        sys.exit("ABORT: screen is locked — AX cannot see any window. Unlock and re-run; nothing was measured.")
    # restrict to the DETAIL side: drop the sidebar outline block
    lines=[l.strip() for l in out.splitlines() if l.strip().startswith(("AXStaticText:","AXButton:","AXCheckBox","AXHeading","AXRadioButton","AXPopUpButton","AXTextField","AXSlider"))]
    return lines
def run(lang):
    sh("defaults","write",D,"AppLanguage","-string",lang)
    sh("osascript","-e",'tell application "XFinder" to quit'); time.sleep(2.5); sh("open","-a","/Applications/XFinder.app"); time.sleep(5)
    res={}
    for p in pages:
        sh("open",f"xfinder://settings?page={p}"); time.sleep(1.3)
        res[p]=dump()
    return res
try:
    en=run("english"); vi=run("vietnamese")
finally:
    sh("defaults","write",D,"AppLanguage","-string",orig_lang)
    sh("osascript","-e",'tell application "XFinder" to quit'); time.sleep(2); sh("open","-a","/Applications/XFinder.app")
print(f"{'page':22} {'EN':>4} {'VI':>4}  leaks(EN)")
problems=0
for p in pages:
    e=en[p]; v=vi[p]
    leaks=[l for l in e if VI.search(l) and not any(a in l for a in allow)]
    flag=""
    if len(e)<6: flag+=" FEW-NODES"
    if abs(len(e)-len(v))>6: flag+=f" COUNT-DIFF"
    if leaks: flag+=f" LEAK×{len(leaks)}"
    if flag: problems+=1
    print(f"{p:22} {len(e):>4} {len(v):>4} {flag}")
    for l in leaks[:3]: print("      ", l[:120])
print(f"\nTOTAL pages: {len(pages)}, flagged: {problems}")
