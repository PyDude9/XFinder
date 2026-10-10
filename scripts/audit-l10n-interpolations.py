#!/usr/bin/env python3
"""Fail when an interpolated Swift string still carries Vietnamese OUTSIDE its \\( ) parts.

Language leak shape #7 (2026-10-10). `audit-l10n-literals.py` judges a literal by what precedes it,
so a string like "\\(L10n.t("Đã gộp "))\\(n)\\(L10n.t(" tập tin ("))\\(pages) trang) → \\(name)" looks
wrapped — yet " trang) → " reaches the English UI as Vietnamese. Found in six places (PDF tools,
QuickShare, UpdateChecker, SystemControls, the menubar flyout) after every other gate said TOTAL 0.

Method: take every string literal that contains an interpolation, delete each balanced \\( … ) —
which removes the L10n.t(...) calls and runtime values — and look at what text is left.

Limit, measured on the very leak that prompted this gate: a Vietnamese word WITHOUT diacritics
(" trang", " tin") is invisible to any diacritic-based check, this one included — "trang" survived
every gate for months. The rendered AX sweep (scripts/sweep-pages-ax.py) is the backstop.

Usage: python3 scripts/audit-l10n-interpolations.py [paths…]   (default: XFinder/)
Prints offending lines and `TOTAL N`; exits 1 when N > 0.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Vietnamese letters: Latin-1 accented letters and Latin Extended Additional, minus × and ÷.
VI = re.compile(r"[À-ÖØ-öø-ÿĂăĐđĨĩŨũƠơƯưẠ-ỹ]")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def strip_interpolations(body: str) -> str:
    out, i = [], 0
    while i < len(body):
        if body.startswith("\\(", i):
            depth, i = 1, i + 2
            in_str = False
            while i < len(body) and depth:
                ch = body[i]
                if ch == '"' and body[i - 1] != "\\":
                    in_str = not in_str
                elif not in_str and ch == "(":
                    depth += 1
                elif not in_str and ch == ")":
                    depth -= 1
                i += 1
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def literals_with_interpolation(line: str):
    """Yield whole interpolated literals, tolerating nested quotes inside \\( )."""
    i = 0
    while True:
        start = line.find('"', i)
        if start < 0:
            return
        j, depth, inner = start + 1, 0, False   # inner: inside a string nested in \\( )
        while j < len(line):
            ch = line[j]
            if ch == "\\":
                if not inner and line.startswith("\\(", j):
                    depth += 1; j += 2; continue
                j += 2; continue                 # an escape, inside or outside
            if depth and ch == '"':
                inner = not inner                # parens inside " tập tin (" must not count
            elif depth and not inner and ch == "(":
                depth += 1
            elif depth and not inner and ch == ")":
                depth -= 1
            elif depth == 0 and ch == '"':
                break
            j += 1
        body = line[start + 1:j]
        if "\\(" in body:
            yield body
        i = j + 1


def main(argv):
    paths = [pathlib.Path(p) for p in argv] or [ROOT / "XFinder"]
    files = [f for p in paths for f in (p.rglob("*.swift") if p.is_dir() else [p])]
    hits = []
    for f in sorted(files):
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//") or "\\(" not in line:
                continue
            for body in literals_with_interpolation(line):
                rest = strip_interpolations(body)
                if VI.search(rest):
                    hits.append(f"{f.relative_to(ROOT) if f.is_relative_to(ROOT) else f}:{n}: …{rest.strip()[:70]}")
    for h in hits:
        print(h)
    print(f"TOTAL {len(hits)} interpolated strings with Vietnamese outside L10n.t")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
