# Security and privacy

## What the app does with your data

Everything happens on your Mac. The app makes **no network connections**,
sends **no telemetry**, has no update checker and no account. Files you drop
are read from disk and the result is written next to them (or to the output
folder you chose in Settings).

## How to check that yourself

```sh
# 1. No networking code in the sources (expect no output):
grep -rnE "URLSession|URLRequest|NWConnection|NWPathMonitor|CFSocket|WKWebView|import Network|import WebKit|http(s)?://" Sources/

# 2. No entitlements and no sandbox exceptions in the built app (expect "no entitlements"-style empty output):
codesign -d --entitlements - /Applications/Mandarin.app

# 3. No open sockets while the app is running (expect no output):
lsof -i -a -c Mandarin
```

The app is not sandboxed (it must read and write wherever you drop files, and
run the helper tools below), so the absence of the network is a property of the
code, which is small enough to audit, rather than something macOS enforces.
Little Snitch or `nettop` will confirm it from the outside.

## Helper tools

Conversions use separate programs you install yourself (ffmpeg, pandoc, unar,
cwebp, LibreOffice; see `THIRD_PARTY.md`). The app passes them local file paths
only. Those programs are not part of this project; keep them updated with
`brew upgrade`.

## Why Accessibility and Input Monitoring

- **Accessibility** lets the app observe global mouse events to notice that you
  are dragging a file, and place the wheel next to the pointer.
- **Input Monitoring** lets it see modifier-key taps (Shift, Command, Control,
  Option) during a drag, which choose the wheel, and Escape to cancel.
- **Automation (Finder)** is asked once, when you use the keyboard flow, so the
  app can ask Finder which files are selected.

The app does not record or store key presses or the mouse path; events are
inspected for the modifier flags and Escape, then discarded.

## Reporting a vulnerability

Please open a private security advisory on the repository (Security tab ->
"Report a vulnerability"). Do not post details in a public issue.
