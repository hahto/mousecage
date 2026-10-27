# Mousecage
Inspired by [Mouselock](https://github.com/mxrlkn/mouselock) by @mxrlkn

On macOS League of Legends doesn't lock the cursor to it's window. With windowed mode or with multiple monitors cursor can slide off the edge and a click can land outside. Mousecage is a small menu bar app that keeps the mouse inside of the game window when it's in front.

## Install

1. Download `Mousecage.dmg` from [Releases](../../releases).
2. Open it and drag **Mousecage** to **Applications**.
3. The app is not notarized, so macOS blocks the first launch. Either
   right-click the app → **Open** → **Open**, or run:
   ```sh
   xattr -d com.apple.quarantine /Applications/Mousecage.app
   ```
4. Grant **Accessibility** access when asked
   (System Settings → Privacy & Security → Accessibility).
   The app picks it up within a second, no restart needed.

## Known limitations

- **Mouse can stutter occasionally.** Every mouse event moves the cursor
  through the window server, which sometimes lags on its own. This happens at
  any polling rate, but it is more frequent at 1000 Hz, so 500 Hz polling is
  recommended.
- **Not notarized.** See Install step 3.

## How it works

- A Quartz event tap (`CGEventTapCreate`) receives every mouse move on its own
  high-priority thread, so nothing else in the app can delay it.
- A second thread polls the window list every 100 ms to find out whether the
  game is the frontmost window and where its bounds are.
- While the game is in front, the tap computes where the cursor should be from
  the mouse deltas, clamps it to the window, and moves it there with
  `CGWarpMouseCursorPosition`.

