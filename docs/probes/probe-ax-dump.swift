// probe-ax-dump.swift — measure what an app's window actually *renders*.
//
// Why this exists: `screencapture` fails on this host (recorded in Claude.md), so
// "does the page show anything?" cannot be answered by looking. It *can* be answered
// by walking the Accessibility tree of the app's window and counting the text nodes
// SwiftUI published. An empty tree is an empty page; a tree with N static-text nodes
// is a rendered page, whatever it looks like.
//
// Usage:  swift docs/probes/probe-ax-dump.swift <pid> [maxDepth]
// Needs:  Accessibility permission for the *calling* process (Terminal / swift).

import ApplicationServices
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2, let pid = pid_t(args[1]) else {
    FileHandle.standardError.write(Data("usage: probe-ax-dump.swift <pid> [maxDepth]\n".utf8))
    exit(2)
}
let maxDepth = args.count >= 3 ? (Int(args[2]) ?? 12) : 12

print("AXIsProcessTrusted (this process): \(AXIsProcessTrusted())")

let app = AXUIElementCreateApplication(pid)

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(el, name as CFString, &v)
    return err == .success ? v : nil
}

func str(_ el: AXUIElement, _ name: String) -> String? {
    attr(el, name) as? String
}

var textNodes = 0
var roleCounts: [String: Int] = [:]
var lines: [String] = []

func walk(_ el: AXUIElement, _ depth: Int, _ path: String) {
    if depth > maxDepth { return }
    let role = str(el, kAXRoleAttribute) ?? "?"
    roleCounts[role, default: 0] += 1

    var label = str(el, kAXTitleAttribute) ?? ""
    if label.isEmpty { label = str(el, kAXDescriptionAttribute) ?? "" }
    let value = str(el, kAXValueAttribute) ?? ""

    if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String
        || role == kAXButtonRole as String || role == kAXCheckBoxRole as String {
        let shown = !value.isEmpty ? value : label
        if !shown.isEmpty {
            textNodes += 1
            lines.append("\(String(repeating: "  ", count: depth))\(role): \(shown)")
        }
    } else if !label.isEmpty {
        lines.append("\(String(repeating: "  ", count: depth))\(role) [\(label)]")
    }

    if let children = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for (i, c) in children.enumerated() {
            walk(c, depth + 1, "\(path).\(i)")
        }
    }
}

guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement] else {
    print("NO WINDOWS attribute on app \(pid)")
    exit(1)
}
print("windows: \(windows.count)")
for (i, w) in windows.enumerated() {
    let title = str(w, kAXTitleAttribute) ?? "(untitled)"
    let subrole = str(w, kAXSubroleAttribute) ?? "?"
    print("--- window \(i): title=\"\(title)\" subrole=\(subrole) ---")
}
for (i, w) in windows.enumerated() {
    lines = []
    walk(w, 0, "w\(i)")
    print("=== window \(i) tree (text nodes so far: \(textNodes)) ===")
    for l in lines.prefix(400) { print(l) }
}
print("TOTAL static-text/value nodes: \(textNodes)")
print("ROLE COUNTS: \(roleCounts.sorted { $0.key < $1.key })")
