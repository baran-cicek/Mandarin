# Third-party tools

The repository and the built app contain **no third-party binaries**. Each tool
below is a separate program that the user installs (`brew bundle` with the
included `Brewfile`, or `install.sh`). Mandarin starts it as a child process
with local file paths as arguments, and never links against it. `ExternalTool`
looks each one up at startup; a missing tool produces a HUD message naming it
and the exact `brew install` command.

| Tool | Used for | How it is used | License | Project |
|---|---|---|---|---|
| ffmpeg | Audio/video conversion, extraction, trimming, GIF export | Separate program, installed by the user | GPL-2.0-or-later (Homebrew's build also links GPL `libx264`/`libx265`, so the effective license is GPL) | https://ffmpeg.org |
| cwebp (libwebp) | Encoding WebP (ImageIO can decode but not encode it) | Separate program, installed by the user | BSD-3-Clause | https://developers.google.com/speed/webp |
| pandoc | Markdown/EPUB/HTML document conversion | Separate program, installed by the user | GPL-2.0-or-later | https://pandoc.org |
| LibreOffice (`soffice`) | Spreadsheet and slide conversion, PDF export | Separate application, installed by the user | MPL-2.0 (some LGPL-2.1-or-later components) | https://www.libreoffice.org |
| unar (The Unarchiver) | Archive extraction (ZIP/TAR/GZIP/RAR) | Separate program, installed by the user | LGPL-2.1-or-later | https://theunarchiver.com |

Because the tools run as separate processes and nothing is distributed together
with them, their licenses do not apply to Mandarin's own MIT-licensed code.

## System tools (part of macOS)

`/usr/bin/zip`, `/usr/bin/tar` and `/usr/bin/gzip` ship with every Mac and are used for
creating archives.
