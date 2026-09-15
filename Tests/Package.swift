// swift-tools-version: 5.9
import PackageDescription

/// Test package for XFinder's pure logic.
///
/// Why a package rather than an Xcode test target: `XFinder.xcodeproj` is a
/// hand-authored classic PBX file (see CLAUDE.md Part 4) where every file needs
/// four correct entries. Bolting a second target onto it by hand is exactly the
/// kind of edit that silently excludes files. A package compiles the same
/// sources directly, runs with `swift test`, and cannot corrupt the app project.
///
/// Only *pure* logic is covered — geometry, classification, rename planning.
/// Anything that needs AppKit, Accessibility or the pasteboard is excluded on
/// purpose: those need a running app and a granted permission, so a unit test
/// asserting them would be theatre.
let package = Package(
    name: "XFinderTests",
    platforms: [.macOS(.v14)],
    targets: [
        .testTarget(
            name: "XFinderLogicTests",
            path: "XFinderLogicTests"
        )
    ]
)
