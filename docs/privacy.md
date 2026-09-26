# Privacy Policy

**App**: QuKi Notes
**Developer**: Scott Kirvan  
**Effective date**: 2026-09-26

---

## The short version

QuKi Notes collects no personal data. There are no accounts, no servers, no analytics, and no tracking of any kind.

---

## What data the app stores

QuKi Notes stores only the notes you type — called **QuKis** — and any images you paste into them. On Android, Windows and Linux they're plain `.md` files (and image files) in a folder on your device: one you choose, or the app's own storage. In the web version they're kept in your browser's storage for the QuKi Notes site, on your device. QuKis never leave your device unless you send them somewhere yourself.

Nothing is synced automatically. Nothing is uploaded in the background. There is no cloud backend.

QuKi Notes also keeps a few settings on your device: the storage location you chose and, on Windows and Linux, the size and position of the window.

## What happens when you send a QuKi

Sending is always a deliberate, user-initiated action (the **Send** button). What happens depends on the platform:

- **Windows and Linux** — the text is copied to your device's system clipboard. That is a local operation. Nothing is transmitted over the network.
- **Android** — the system share sheet opens and you choose which app receives the text. QuKi Notes hands the text to the app you pick; it does not see or store where it went.

In both cases the data goes to a destination **you** chose, not to the app developer.

## Network requests the app makes

QuKi Notes itself has no server to talk to, but a few things you do can reach the internet:

- **Images from the web.** If a QuKi contains an image linked by web address (`https://…`), QuKi Notes downloads that image from its server when the QuKi is shown. As with any web request, that server sees your IP address and the time of the request. No QuKi content is sent. Images you paste in are stored locally and involve no network access.
- **Links.** Tapping a link in a QuKi, or in the Help dialog, opens that website.
- **The web version.** The web version is itself a website, hosted on GitHub Pages. When your browser loads it, GitHub receives the usual request information (such as your IP address), as it does for any GitHub Pages site. Your QuKis stay in your browser and are not sent to GitHub.

## The command-line tools and AI assistants

The optional `quki` command-line tool and the `quki-mcp` server work only on the QuKi folder on your own computer, and make no network requests themselves. If you connect `quki-mcp` to an AI assistant, the assistant can read, create, change and delete QuKis, and whatever it reads is sent to that assistant's provider under **their** privacy policy, not this one. Only connect it to assistants you trust with your notes.

## Device backups

On Android, if you use app storage and your device's backup is turned on, Android may include your QuKis in its device backup. That backup is handled by Android and Google under your device settings, not by QuKi Notes. QuKis in filesystem storage (`Documents/QuKi_Notes`) are covered by whatever backup or sync you use for that folder.

## Analytics, crash reporting, and telemetry

None. This is a current design decision.

## Permissions

QuKi Notes requests only the permissions it needs to function on each platform. On Android that means internet access (for web images and links) and, only if you choose filesystem storage, **All files access**, so it can keep your QuKis in your `Documents` folder. It does not request location, contacts, microphone, camera, or any other sensitive permission.

## Third parties

QuKi Notes does not share data with any third party. There are no advertising SDKs, analytics SDKs, or crash-reporting SDKs in the app.

## Children

QuKi Notes does not knowingly collect information from anyone. It collects no information from anyone, regardless of age.

## Changes to this policy

If anything here ever changes, the updated policy will be posted at this URL with a new effective date. The core commitment — no data collection — is not subject to change.

## Contact

Questions? Open an issue on [GitHub](https://github.com/ScottKirvan/QuKi-Notes/issues) or reach out on [Discord](https://discord.gg/TN6XJSNK5Y).
