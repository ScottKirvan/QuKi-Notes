# QuKi Notes &nbsp; [![starline](https://raw.githubusercontent.com/ScottKirvan/QuKi-Notes/refs/heads/starlines/ScottKirvan/QuKi-Notes/starline.svg)](https://github.com/qoomon/starlines)

<div align="center">

<img src="https://raw.githubusercontent.com/ScottKirvan/QuKi-Notes/refs/heads/main/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png" alt="QuKi Notes" width="160" />

**Open. Type. Done.**

Frictionless scratchpad and pasteboard -- a loose-leaf, digital zibaldone

[![CI](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml/badge.svg)](https://github.com/ScottKirvan/QuKi-Notes/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ScottKirvan/QuKi-Notes)](https://github.com/ScottKirvan/QuKi-Notes/releases/latest)
[![License: MIT](https://img.shields.io/github/license/ScottKirvan/QuKi-Notes)](LICENSE.md)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](project)
[![Web](https://img.shields.io/badge/Web-PWA-5A0FC8?logo=googlechrome&logoColor=white)](#platform-support)
[![Android](https://img.shields.io/badge/Android-Capacitor-3DDC84?logo=android&logoColor=white)](#platform-support)
[![Windows](https://img.shields.io/badge/Windows-Electron-0078D4?logo=windows&logoColor=white)](#platform-support)
[![Linux](https://img.shields.io/badge/Linux-Electron-FCC624?logo=linux&logoColor=black)](#platform-support)
[![Discord](https://img.shields.io/discord/1052011377415438346?label=discord&color=00ACD7)](https://discord.gg/TN6XJSNK5Y)

[Download](https://scottkirvan.com/QuKi-Notes/downloads.html) &nbsp;·&nbsp;
[Docs](https://scottkirvan.com/QuKi-Notes/) &nbsp;·&nbsp;
[Discord](https://discord.gg/TN6XJSNK5Y) &nbsp;·&nbsp;
[Report Bug](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=bug_report.md) &nbsp;·&nbsp;
[Request Feature](https://github.com/ScottKirvan/QuKi-Notes/issues/new?template=feature_request.md)

</div>

---

## What is QuKi Notes?

QuKi Notes is a frictionless scratchpad and pasteboard -- your loose-leaf, digital zibaldone.  It launches to a blank page ready for input, with a searchable list of existing notes just a click away. Type a thought, draft a post, check something off a list, paste a link, or log that idea for your next invention. Use the content right there, send it somewhere, or let it drift down the list as newer things arrive.

A QuKi doesn't need a destination. Maybe it just needs somewhere to live -- temporarily -- off your mind and available if it ever turns out to be useful. No vaults, no file hierarchies, and no productivity systems to distract.  Sorting is automatic, driven entirely by touch and engagement: touch a QuKi and it pops back to the top.

The project prioritizes **radical simplicity**  and **open extensibility**  -- a real core API with a CLI and an MCP server built right alongside the app, powered entirely by open, plain text markdown. Read the [manifesto](notes/archive/dev/manifesto.md) for the full philosophy.


---

## Features

| Feature                                  | Details                                                                                                                                                                                                                                                                                                   |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cross Plaform                            | Available for Android, Windows, Linux, and as an installable web app (use the web app on IOS, iPad, & MacOS)                                                                                                                                                                                              |
| **Instant capture**                      | App opens to a blank editor — no title field, no setup, cursor ready                                                                                                                                                                                                                                      |
| **Auto-save**                            | 2 s idle debounce + 30 s periodic + app lifecycle hooks; no save button                                                                                                                                                                                                                                   |
| **QuKis list**                           | Newest-first, case-insensitive full-text search, swipe-to-delete                                                                                                                                                                                                                                          |
| **Trash**                                | Soft-deleted QuKis held for 30 days before automatic purge; restore or delete permanently any time                                                                                                                                                                                                        |
| **Live-preview markdown editor**         | The note renders as you type — headings, bold/italic/strikethrough, links, images, checkboxes, blockquotes, lists, tables and fenced code all render inline. The element the cursor is inside reveals its raw markdown source; move the cursor away and it renders again. No mode switch, no tap-to-flip. |
| **Images**                               | Paste an image directly into a note; also renders images referenced by a remote `http(s)://` URL                                                                                                                                                                                                          |
| **Tables & code blocks**                 | GFM pipe tables and fenced code blocks render fully, reverting to raw source while the cursor is inside them                                                                                                                                                                                              |
| **Link tap**                             | Tap a rendered link to open it in the platform's default browser                                                                                                                                                                                                                                          |
| **Checkbox tap**                         | Tap a rendered checkbox to toggle it without entering edit mode                                                                                                                                                                                                                                           |
| **Formatting toolbar**                   | Bold, italic, strikethrough, inline code, heading (cycles normal → H1 → H2 → H3), unordered/ordered/task lists, indent/dedent                                                                                                                                                                             |
| **List auto-continue**                   | Enter at the end of a list item continues the list; Enter on an empty item exits it                                                                                                                                                                                                                       |
| **Plain-text toggle**                    | Switch the entire note to a raw monospace text field for bulk edits or raw paste                                                                                                                                                                                                                          |
| **Storage location**                     | Choose a real folder on disk (Electron, and Android with all-files access) or private app storage; the web app uses the browser's own persistent origin storage                                                                                                                                           |
| **Share out / share in**                 | Send a QuKi via the system share sheet (Android, Windows, macOS) or clipboard (Linux); receive shared text from another app directly into a new QuKi (Android)                                                                                                                                            |
| **Obsidian-compatible theming**          | Every colour and font is an Obsidian CSS variable name, defaulting to the GitHubDHC theme, so an Obsidian theme can restyle the whole app                                                                                                                                                                 |
| **Installable, offline-capable web app** | The web build is a full PWA — installs to a home screen, works with no network                                                                                                                                                                                                                            |
| **Desktop keyboard shortcuts**           | New QuKi and Send shortcuts on Windows / Linux                                                                                                                                                                                                                                                            |
| **Window-state persistence**             | Size and position remembered between sessions (Windows / Linux)                                                                                                                                                                                                                                           |
| **No telemetry**                         | No analytics, no crash reporting, no tracking — ever                                                                                                                                                                                                                                                      |


---

## Getting the App

Download the latest release from [**GitHub Releases**](https://github.com/ScottKirvan/QuKi-Notes/releases/latest), or just open the [web app](https://scottkirvan.github.io/QuKi-Notes/) directly and install it from the browser.

| Platform | Artifact | Install |
|---|---|---|
| Android | `.apk` | Sideload directly or via `adb install` |
| Windows | `.exe` | Run the installer |
| Linux | `.AppImage` | Mark executable and run |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow. In short:

- Read the [manifesto](notes/archive/dev/manifesto.md) first — it's short and normative.
- [Conventional Commits](https://www.conventionalcommits.org/): `feat:` is reserved for genuinely new user-facing capability; bug fixes and corrections — even ones that close a tracked issue — use `fix:`.
- Branch from `main`, one concern per branch and PR.

---

## License

MIT — see [LICENSE.md](LICENSE.md).

---

## Contact

- **Issues & PRs**: [github.com/ScottKirvan/QuKi-Notes](https://github.com/ScottKirvan/QuKi-Notes)
- **Discord**: [discord.gg/TN6XJSNK5Y](https://discord.gg/TN6XJSNK5Y) — I'm `cptvideo`
- **LinkedIn**: [linkedin.com/in/scottkirvan](https://www.linkedin.com/in/scottkirvan/)
- **User Docs**: [scottkirvan.github.io/QuKi-Notes](https://scottkirvan.github.io/QuKi-Notes/)

[CHANGELOG](notes/CHANGELOG.md)
