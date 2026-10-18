#!/usr/bin/env python3
"""
write-rule.py — produce rule.json matching XFinder's SnapMemory.Store Codable shape.

This does NOT write anything into XFinder or the user's defaults. It only
builds the JSON file the integrator can hand to whatever mechanism actually
installs a SnapMemory rule into the running app (file import, a debug menu,
direct UserDefaults write from inside XFinder's own code, etc. — not decided
here, by design, per the task brief).

Swift's synthesized Codable for an enum with associated values encodes as
{"<caseName>": {"_0": <value>}} for a single unlabeled associated value, and
{"<caseName>": {}} for a case with no associated value. JSONEncoder's default
date strategy (.deferredToDate) encodes Date as seconds since the Swift/
Foundation reference date 2001-01-01T00:00:00Z (NOT Unix epoch).

Usage:
    python3 write-rule.py \
        --out rule.json \
        --bundle-id com.xfinder.e2e.snapmem \
        --app-name "SnapMem Target" \
        --display-uuid 37D8832A-2D66-02CA-B9F7-8F30A301B230 \
        --display-name "Built-in Retina Display" \
        --pixel-width 3456 --pixel-height 2234 \
        --is-builtin true \
        --layout-kind snap --layout-target leftHalf

    # fullscreen:
    python3 write-rule.py --out rule.json --bundle-id ... --layout-kind fullscreen ...

    # explicit frame (normalized 0..1 rect), e.g. for a custom .frame case:
    python3 write-rule.py --out rule.json --bundle-id ... --layout-kind frame \
        --frame-x 0.0 --frame-y 0.0 --frame-width 0.5 --frame-height 1.0 ...

Multiple displays in the arrangement: pass --display-uuid/--display-name/
--pixel-width/--pixel-height/--is-builtin as comma-separated parallel lists
(one entry per display in the arrangement) — the SAME counts in each list,
in the order you want BEFORE the required sort is applied. This script
applies the documented sort itself: builtin first, then by uuid, so the
caller does not have to pre-sort.

The primary display (the one `layout` is relative to / where the window
should land) is given once via the singular --display-* flags above when
there is exactly one display in the arrangement; for a multi-display
arrangement, mark the primary with --primary-index (0-based index into the
comma lists) and the `display` field of the Rule is set to that entry's
DisplayKey (DisplayKey, singular — see shape below).

NOTE ON SHAPE: `Rule.display: DisplayKey` is the single display the layout
targets; `Rule.arrangement: Arrangement { displays: [DisplayKey] }` is the
whole recognized set of connected displays (for matching "is this the same
multi-monitor setup the rule was recorded under"). Both are produced here.
"""
import argparse
import datetime
import json
import sys


SWIFT_REFERENCE_DATE = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)

VALID_TARGETS = {
    "leftHalf", "rightHalf", "topHalf", "bottomHalf",
    "topLeft", "topRight", "bottomLeft", "bottomRight",
    "maximize", "center",
    "leftThird", "centerThird", "rightThird",
    "leftTwoThirds", "rightTwoThirds",
    "focus",
}


def str2bool(v):
    if isinstance(v, bool):
        return v
    if v.lower() in ("true", "1", "yes", "y"):
        return True
    if v.lower() in ("false", "0", "no", "n"):
        return False
    raise argparse.ArgumentTypeError(f"expected true/false, got {v!r}")


def swift_date_seconds(dt=None):
    """Seconds since 2001-01-01T00:00:00Z, matching JSONEncoder's default
    (.deferredToDate) Date encoding strategy."""
    if dt is None:
        dt = datetime.datetime.now(datetime.timezone.utc)
    delta = dt - SWIFT_REFERENCE_DATE
    return delta.total_seconds()


def build_display_key(uuid, name, pixel_width, pixel_height, is_builtin):
    return {
        "uuid": uuid,
        "name": name,
        "pixelWidth": pixel_width,
        "pixelHeight": pixel_height,
        "isBuiltin": is_builtin,
    }


def sorted_displays(displays):
    """Arrangement.displays sort order per the spec: builtin first, then by uuid."""
    return sorted(displays, key=lambda d: (not d["isBuiltin"], d["uuid"]))


def build_layout(args):
    kind = args.layout_kind
    if kind == "snap":
        if not args.layout_target:
            sys.exit("error: --layout-kind snap requires --layout-target")
        if args.layout_target not in VALID_TARGETS:
            sys.exit(f"error: unknown --layout-target {args.layout_target!r}; valid: {sorted(VALID_TARGETS)}")
        return {"snap": {"_0": args.layout_target}}
    elif kind == "fullscreen":
        return {"fullscreen": {}}
    elif kind == "frame":
        missing = [f for f in ("frame_x", "frame_y", "frame_width", "frame_height") if getattr(args, f) is None]
        if missing:
            sys.exit(f"error: --layout-kind frame requires --frame-x/--frame-y/--frame-width/--frame-height (missing: {missing})")
        return {
            "frame": {
                "_0": {
                    "x": args.frame_x,
                    "y": args.frame_y,
                    "width": args.frame_width,
                    "height": args.frame_height,
                }
            }
        }
    else:
        sys.exit(f"error: unknown --layout-kind {kind!r}; must be snap, fullscreen, or frame")


def parse_csv_or_single(value):
    if value is None:
        return None
    return [v.strip() for v in value.split(",")]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", required=True, help="output path for rule.json")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--app-name", required=True)

    # Single-display convenience flags (used directly as both `display` and
    # the sole entry of `arrangement.displays` when --multi-arrangement is
    # not given).
    p.add_argument("--display-uuid", required=True, help="comma-separated if multiple displays in the arrangement")
    p.add_argument("--display-name", required=True, help="comma-separated, parallel to --display-uuid")
    p.add_argument("--pixel-width", required=True, help="comma-separated, parallel to --display-uuid")
    p.add_argument("--pixel-height", required=True, help="comma-separated, parallel to --display-uuid")
    p.add_argument("--is-builtin", required=True, help="comma-separated true/false, parallel to --display-uuid")
    p.add_argument("--primary-index", type=int, default=0, help="0-based index into the comma lists for the display the layout targets (default 0)")

    p.add_argument("--layout-kind", required=True, choices=["snap", "fullscreen", "frame"])
    p.add_argument("--layout-target", help="required when --layout-kind snap; one of: " + ", ".join(sorted(VALID_TARGETS)))
    p.add_argument("--frame-x", type=float)
    p.add_argument("--frame-y", type=float)
    p.add_argument("--frame-width", type=float)
    p.add_argument("--frame-height", type=float)

    p.add_argument("--updated-at", help="ISO8601 UTC timestamp; default now")
    p.add_argument("--last-outcome", choices=["success", "failed", "skipped"], default=None,
                    help="omit for null lastOutcome")
    p.add_argument("--last-applied-at", help="ISO8601 UTC timestamp; omit for null lastAppliedAt")

    args = p.parse_args()

    uuids = parse_csv_or_single(args.display_uuid)
    names = parse_csv_or_single(args.display_name)
    pws = [int(x) for x in parse_csv_or_single(args.pixel_width)]
    phs = [int(x) for x in parse_csv_or_single(args.pixel_height)]
    builtins = [str2bool(x) for x in parse_csv_or_single(args.is_builtin)]

    n = len(uuids)
    if not (len(names) == len(pws) == len(phs) == len(builtins) == n):
        sys.exit(
            "error: --display-uuid/--display-name/--pixel-width/--pixel-height/--is-builtin "
            f"must all have the same comma-separated length (got {n}, {len(names)}, {len(pws)}, {len(phs)}, {len(builtins)})"
        )
    if not (0 <= args.primary_index < n):
        sys.exit(f"error: --primary-index {args.primary_index} out of range for {n} display(s)")

    all_displays = [
        build_display_key(uuids[i], names[i], pws[i], phs[i], builtins[i])
        for i in range(n)
    ]
    primary_display = all_displays[args.primary_index]
    arrangement_displays = sorted_displays(all_displays)

    layout = build_layout(args)

    updated_dt = (
        datetime.datetime.fromisoformat(args.updated_at).astimezone(datetime.timezone.utc)
        if args.updated_at else datetime.datetime.now(datetime.timezone.utc)
    )
    updated_seconds = swift_date_seconds(updated_dt)

    last_applied_seconds = None
    if args.last_applied_at:
        la_dt = datetime.datetime.fromisoformat(args.last_applied_at).astimezone(datetime.timezone.utc)
        last_applied_seconds = swift_date_seconds(la_dt)

    rule = {
        "bundleID": args.bundle_id,
        "appName": args.app_name,
        "arrangement": {"displays": arrangement_displays},
        "display": primary_display,
        "layout": layout,
        "updatedAt": updated_seconds,
    }
    if args.last_outcome is not None:
        rule["lastOutcome"] = {args.last_outcome: {}}
    else:
        rule["lastOutcome"] = None
    if last_applied_seconds is not None:
        rule["lastAppliedAt"] = last_applied_seconds
    else:
        rule["lastAppliedAt"] = None

    store = {
        "version": 1,
        "rules": [rule],
    }

    with open(args.out, "w") as f:
        json.dump(store, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"wrote {args.out}")
    print(json.dumps(store, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
