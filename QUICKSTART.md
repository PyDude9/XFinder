# XFinder Quick Start Guide

Get XFinder up and running in 5 minutes.

---

## Prerequisites

✅ Xcode 14+ installed  
✅ macOS 12+  
✅ 1 GB disk space  

## 1️⃣ Clone/Navigate to Project

```bash
cd /Users/wolong/github/XFinder
ls -la  # Should see: XFinder/, README.md, Claude.md
```

## 2️⃣ Open in Xcode

```bash
open XFinder.xcodeproj
```

Or via Xcode UI:
1. Xcode → File → Open
2. Navigate to `/Users/wolong/github/XFinder/XFinder.xcodeproj`
3. Click **Open**

## 3️⃣ Select Target & Build

In Xcode:
1. Select **XFinder** scheme (top-left dropdown)
2. Select **My Mac** as destination
3. Press **Cmd+B** to build

## 4️⃣ Run the App

Press **Cmd+R** or click the **Play** button.

XFinder should launch in 2-3 seconds.

## 5️⃣ Test Key Features

### Clipboard Tab
- Copy some text (Cmd+C)
- Switch to XFinder → **Clipboard** tab
- Your text should appear as a card

### Files Tab
- Click **Files** tab
- Click home icon in path bar
- Files in home directory listed

### Tools Tab
- Click **Tools** tab
- See grid of 9 tools (Compress, PDF, etc.)

### System Monitor Tab
- Click **System** tab
- See CPU, Memory, Storage, Battery stats

### Side Notes
- Click **+** button (floating) or **🗒️ Ghi chú** in right panel
- Create a quick note
- Notes saved automatically

### Menubar
- Look for **XFinder icon** in top-right menu bar
- Click to open flyout
- See brightness, volume, battery, CPU temp

## 🎮 Keyboard Shortcuts

| Key | Action |
|:---|:---|
| `⌘⇧V` | Toggle Clipboard tab |
| `⌘⇧E` | Toggle Files tab |
| `⌘⇧T` | Toggle Tools tab |
| `⌘⇧N` | Toggle Side Notes |
| `⌘,` | Open Settings |
| `⌘Q` | Quit XFinder |

## 🔧 Next Steps

### View Project Structure
```bash
find XFinder -name "*.swift" | head -20
```

### Check File Locations
- **Models**: `XFinder/Models/` (5 files)
- **Managers**: `XFinder/Core/` (4 files)
- **Views**: `XFinder/Views/` (7 files)
- **App**: `XFinder/App/` (2 files)

### Build from Command Line
```bash
xcodebuild -scheme XFinder -configuration Debug
```

### Open Built App
```bash
open build/Debug/XFinder.app
```

### View Build Logs
```bash
xcodebuild -scheme XFinder -configuration Debug | tail -50
```

## 📚 Documentation

- **Full Spec**: See `Claude.md`
- **Overview**: See `README.md`
- **Build Guide**: See `BUILDING.md`
- **Status**: See `DEVELOPMENT_STATUS.md`

## 🐛 Troubleshooting

### "Symbol not found" error
```bash
# Clean build cache
rm -rf build/
xcodebuild -scheme XFinder -configuration Debug
```

### App crashes on launch
```bash
# Create required directory
mkdir -p ~/Library/Application\ Support/XFinder
# Rebuild
xcodebuild -scheme XFinder -configuration Debug
```

### Menubar icon missing
- Check System Preferences → General → Login Items
- Ensure XFinder is running

### Settings not saving
- Verify `UserDefaults` permissions
- Check `~/Library/Preferences/com.xfinder.app.plist`

## 💡 Tips

1. **Use Xcode's breakpoints** (Cmd+\) to debug
2. **Check Console output** (Cmd+Shift+C) for logs
3. **Profile with Instruments** (Cmd+I) for performance
4. **Use Preview canvas** for SwiftUI views
5. **Press Escape** to dismiss popover

## 📞 Need Help?

See `BUILDING.md` for detailed build instructions or contact: **thang0todev@gmail.com**

---

**Time to first run**: ~2-3 minutes  
**Confidence level**: 🟢 Ready to build!
