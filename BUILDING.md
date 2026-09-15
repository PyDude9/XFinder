# XFinder Build Guide

## Prerequisites

- **Xcode**: 14.0 or later
- **macOS**: 12.0 or later for development
- **Swift**: 5.8+
- **CocoaPods** (optional, for dependencies)

## Development Setup

### 1. Clone Repository
```bash
cd /Users/wolong/github/XFinder
```

### 2. Install Dependencies (if needed)
Since Phase 1 uses only standard Apple frameworks, no additional dependencies are required.

**Future dependencies** (Phase 2+):
- SQLCipher (encrypted database)
- Vision framework (OCR)
- Metal framework (GPU monitoring)

### 3. Open in Xcode
```bash
open XFinder.xcodeproj
```

Or from the terminal:
```bash
xcodebuild -scheme XFinder -configuration Debug
```

## Build Targets

### Debug Build
```bash
xcodebuild \
  -scheme XFinder \
  -configuration Debug \
  -derivedDataPath ./build
```

### Release Build
```bash
xcodebuild \
  -scheme XFinder \
  -configuration Release \
  -derivedDataPath ./build
```

### Archive for Distribution
```bash
xcodebuild \
  -scheme XFinder \
  -configuration Release \
  -archivePath ./build/XFinder.xcarchive \
  archive
```

## Running the App

### From Xcode
1. Select **XFinder** scheme
2. Select target device (My Mac, Simulator, etc.)
3. Press **Cmd+R** or click **Play** button

### From Command Line
```bash
# Build and run
xcodebuild -scheme XFinder -configuration Debug && \
open ./build/Debug/XFinder.app

# Or directly
open build/Debug/XFinder.app
```

## Code Signing

For App Store distribution:
```bash
# Create provisional profile
xcodebuild \
  -scheme XFinder \
  -configuration Release \
  -archivePath ./build/XFinder.xcarchive \
  archive \
  -signingStyle automatic
```

## Testing

Currently no unit tests are included in Phase 1.

**Planned for Phase 2**:
- Unit tests for managers (Clipboard, FileSystem, SystemMonitor)
- UI tests for main window
- Database integration tests

Run tests (when available):
```bash
xcodebuild \
  -scheme XFinder \
  -configuration Debug \
  test
```

## Troubleshooting

### Issue: "XFinder is not an app"
**Solution**: Ensure Xcode is building for macOS, not iOS.
```bash
xcodebuild -showsdks | grep macosx
```

### Issue: "Code signing error"
**Solution**: Update code signing settings in Xcode:
1. Select project
2. **Signing & Capabilities**
3. Select your Apple Developer Team

### Issue: "Framework not found"
**Solution**: Ensure all frameworks are linked:
```bash
xcodebuild \
  -scheme XFinder \
  -showBuildSettings | grep FRAMEWORK_SEARCH_PATHS
```

### Issue: "Database permission error"
**Solution**: Ensure Application Support directory exists:
```bash
mkdir -p ~/Library/Application\ Support/XFinder
```

## Performance Testing

### Memory Profiling
```bash
xcodebuild \
  -scheme XFinder \
  -configuration Debug \
  -enableThreadSanitizer YES
```

Then open in Instruments:
```bash
open build/Debug/XFinder.app
# Xcode → Debug → Instruments → Memory
```

### CPU Profiling
```bash
# Same build as above
# Xcode → Debug → Instruments → System Trace
```

## Continuous Integration

For automated builds (GitHub Actions, CircleCI, etc.):

```yaml
# Example GitHub Actions workflow
name: Build XFinder

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build
        run: |
          xcodebuild -scheme XFinder -configuration Release
      - name: Archive
        run: |
          xcodebuild -scheme XFinder -configuration Release \
            -archivePath build/XFinder.xcarchive archive
```

## Distribution

### App Store
1. Create App Store Connect entry
2. Generate provisioning profiles
3. Archive app (see above)
4. Upload via Transporter or Xcode

### Direct Distribution
```bash
# Create a DMG
hdiutil create -volname "XFinder" \
  -srcfolder ./build/Release/XFinder.app \
  -ov -format UDZO \
  XFinder.dmg
```

### Notarization (Required for Gatekeeper)
```bash
# Upload for notarization
xcrun altool --notarize-app \
  -f XFinder.dmg \
  -t osx \
  --primary-bundle-id com.xfinder.app \
  -u <appleid> \
  -p <app-specific-password>

# Check status
xcrun altool --notarization-history 0 \
  -u <appleid> \
  -p <app-specific-password>

# Staple notarization
xcrun stapler staple XFinder.dmg
```

## Documentation

- **Architecture**: See `CLAUDE.md` Part 4
- **API Reference**: See inline Swift documentation (`///` comments)
- **User Guide**: See README.md

## Debugging

### Enable Debug Output
```bash
# Set environment variable
export XFINDER_DEBUG=1
xcodebuild -scheme XFinder -configuration Debug
```

### Breakpoints
1. Xcode → Product → Scheme → Edit Scheme
2. **Run** tab → **Pre-launch** actions
3. Add breakpoint conditions

### Console Output
View in Xcode:
- **Debug** → **Activate Breakpoint**
- **View** → **Debug Area** → **Show Console**

## Next Steps

- Proceed with Phase 2 implementation
- Add unit tests
- Optimize performance
- Submit to App Store

---

**Last Updated**: 2025-09-12  
**Phase**: 1 (MVP)
