# Switcher

Windows-style app switching on your Mac. Hold ⌘, tap Tab to move through your open apps, and let go of ⌘ to jump to the one that's highlighted.

## Install
1. Install Apple's command line tools once: `xcode-select --install`
2. Build and install:
   ```sh
   cd AppSwitcher
   ./build.sh --install
   ```
3. macOS asks for Accessibility access. Open System Settings, then Privacy & Security, then Accessibility, and turn on Switcher. It starts working within a second.

## Use it
| Keys (while holding ⌘) | What happens |
| --- | --- |
| Tab | Next app |
| Shift + Tab, `, ← | Previous app |
| → | Next app |
| Let go of ⌘ | Switch to the highlighted app |
| Esc | Cancel |
| Q | Quit the highlighted app |
| H | Hide the highlighted app |

You can also point at an icon with the mouse and click it.

Apps are listed most recently used first, so a quick ⌘Tab flips between your last two apps. Hidden apps show faded. Switching to an app with everything minimized brings a window back, and an app with no windows opens a new one, just like clicking it in the Dock.

## Menu bar
The icon in the menu bar has Open at Login and Quit. Quitting gives you back the Mac's own ⌘Tab.

## Good to know
- After rebuilding, macOS may ask for Accessibility access again. Remove the old Switcher entry in that list and turn on the new one.
- While you type in a password field, macOS blocks all keyboard hooks, so ⌘Tab does nothing there.
- If Switcher ever crashes and the Mac's own ⌘Tab stays off, open Switcher and quit it from the menu bar, or log out and back in.
