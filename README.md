# Backspin

A tiny macOS helper that reverses and smooths scrolling for wheel mice, and leaves your trackpad alone.

macOS has one "Natural scrolling" switch for both the trackpad and the mouse, and no smooth scrolling for mouse wheels. Backspin fixes both for the mouse only: wheel notches scroll the traditional way and glide instead of jumping, while the trackpad (and Magic Mouse) keep natural scrolling exactly as they are.

It's a single Swift file of about 250 lines, built with Apple's own frameworks and nothing else. No settings window, no network access, no updates, no dependencies. You can read the whole thing before you give it Accessibility access.

## Install

You need macOS 14 (Sonoma) or later and Apple's command line tools (`xcode-select --install`).

```bash
git clone https://github.com/baseddesigner/backspin.git
cd backspin
./install.sh
```

That builds `Backspin.app` into `~/Applications` and starts it at every login.

**Then give it Accessibility access.** macOS doesn't always list a self-built app on its own, so:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Drag `~/Applications/Backspin.app` into the list (or click **+**, press ⌘⇧G and type `~/Applications`).
3. Make sure its switch is on.

Backspin starts working within a couple of seconds. You only do this once: the installer signs the app with a certificate created on your Mac, so rebuilds keep the permission.

## What it does

- **Mouse wheel and horizontal wheel:** reversed and smoothed.
- **Trackpad and Magic Mouse:** untouched.
- **Shift + wheel:** scrolls sideways.
- **⌘, ⌃ or ⌥ + wheel:** reversed but not smoothed, so zooming stays precise.
- **Smoothing follows your display:** each glide runs at the refresh rate of the screen the pointer is on (120 Hz on ProMotion, 60 Hz on most external monitors).

## Settings

Change a value, then restart Backspin:

```bash
defaults write io.github.baseddesigner.backspin smoothing 0.12
launchctl kickstart -k gui/$(id -u)/io.github.baseddesigner.backspin
```

| Key | Default | What it does |
| --- | --- | --- |
| `smoothing` | `0.08` | Glide length in seconds. Higher glides longer. |
| `step` | `35` | Minimum pixels per wheel notch. |
| `speed` | `3` | Multiplier on macOS's own scroll acceleration. |
| `smooth` | `true` | Turn smoothing off to only reverse. |
| `reverseVertical` | `true` | Reverse the main wheel. |
| `reverseHorizontal` | `true` | Reverse the horizontal wheel. |

To go back to the defaults: `defaults delete io.github.baseddesigner.backspin`, then restart it.

## Uninstall

```bash
./install.sh uninstall
```

Then remove Backspin from **Privacy & Security → Accessibility**.

## How it works

Backspin listens to scroll events through a macOS event tap. Events marked as continuous (trackpad, Magic Mouse) pass straight through. For wheel events it flips the direction, holds the notch back, and delivers it as small pixel steps on each display frame, easing out toward the end. Reversing direction mid-glide drops the old glide so it feels immediate.

Smoothed scrolling reaches apps as pixel-precise scrolling, like a trackpad's. That's what makes it smooth, and it's the same approach other smooth-scrolling tools use. If one app ever behaves oddly, that's the likely cause.

Logs go to `/tmp/backspin.log`. Run the binary with `--debug` to log every wheel event.

## Status

Built for and tested on a MacBook Pro (Apple silicon) with a Logitech MX Master 3S. Other mice and apps may behave differently. Issues and pull requests are welcome.

## License

[MIT](LICENSE)
