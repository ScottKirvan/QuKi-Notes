# Privacy Policy

**App**: QuKi Notes
**Developer**: Scott Kirvan  
**Effective date**: 2026-11-26

---

## The short version

QuKi Notes collects no personal data. There are no accounts, no analytics, no telemetry, and no tracking of any kind. The app has no server that stores your notes and sends nothing on its own. The one thing it can send is a bug or feature report, and only when you tap **Send** after seeing exactly what will go. See [Reporting bugs and requests](#reporting-bugs-and-requests).

---

## What data the app stores

QuKi Notes stores only the notes you type — called **QuKis** — and any images you paste into them. On Android, Windows and Linux they're plain `.md` files (and image files) in a folder on your device: one you choose, or the app's own storage. In the web version they're kept in your browser's storage for the QuKi Notes site, on your device. QuKis never leave your device unless you send them somewhere yourself.

Nothing is synced automatically. Nothing is uploaded in the background. There is no cloud backend.

QuKi Notes also keeps a few settings on your device: the storage location you chose and, on Windows and Linux, the size and position of the window. It also keeps a small [failure log](#the-failure-log-on-your-device) on your device, which is never sent anywhere on its own.

## What happens when you send a QuKi

Sending is always a deliberate, user-initiated action (the **Send** button). What happens depends on the platform:

- **Windows and Linux** — the text is copied to your device's system clipboard. That is a local operation. Nothing is transmitted over the network.
- **Android** — the system share sheet opens and you choose which app receives the text. QuKi Notes hands the text to the app you pick; it does not see or store where it went.

In both cases the data goes to a destination **you** chose, not to the app developer.

## Network requests the app makes

QuKi Notes has no server that holds your notes. Apart from a problem report you choose to send (see [Reporting bugs and requests](#reporting-bugs-and-requests)), the only things that reach the internet are things you do:

- **Images from the web.** If a QuKi contains an image linked by web address (`https://…`), QuKi Notes downloads that image from its server when the QuKi is shown. As with any web request, that server sees your IP address and the time of the request. No QuKi content is sent. Images you paste in are stored locally and involve no network access.
- **Links.** Tapping a link in a QuKi, or in the Help dialog, opens that website.
- **Spell-check dictionaries (Linux desktop app).** On Linux, the desktop app downloads the spell-check dictionary for your language from Google's servers the first time it needs one, as the Electron framework it's built on does by default. Only the dictionary is requested; no QuKi content is sent. On Windows, Android and the web version, spell check uses your system's or browser's own spellchecker.
- **The web version.** The web version is itself a website, served by Cloudflare at qukinotes.scottkirvan.com. When your browser loads it, Cloudflare receives the usual request information (such as your IP address), as it does for any website it serves. Your QuKis stay in your browser and are not sent to Cloudflare.

## The command-line tools and AI assistants

The optional `quki` command-line tool and the `quki-mcp` server work only on the QuKi folder on your own computer, and make no network requests themselves. If you connect `quki-mcp` to an AI assistant, the assistant can read, create, change and delete QuKis, and whatever it reads is sent to that assistant's provider under **their** privacy policy, not this one. Only connect it to assistants you trust with your notes.

## Reporting bugs and requests

In Settings, under Diagnostics, **Report a problem** opens a form for a bug, a feature request or other feedback. Nothing is sent until you tap **Send**, and before that you can see and edit everything that will go: the title, your description, a "Details" box (the app version, build and platform) and, only if you tick it, the failure log. QuKi Notes never puts the text of your QuKis in a report. Don't add anything private to one.

**Reports are public.** **Send** posts your report to a small relay server, which files it as a public issue on the QuKi Notes project's GitHub page, so anyone can read it. You don't need a GitHub account. The relay is run by the developer, Scott Kirvan, as a Cloudflare Worker at report.scottkirvan.com, and it is shared with the developer's other apps. It does one job: it checks the report and files the issue, labelled as a user report. According to its documentation it keeps nothing: it doesn't store reports, doesn't log what is in them or the IP addresses they came from, and has Cloudflare's Workers logs turned off. When something fails it logs only which step failed and its status code. Cloudflare, which hosts it, sees each request as it passes through, as it does for any website it serves ([Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/)). Once the issue exists, what's in it is public and under [GitHub's privacy policy](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

**Other ways to report.** The form also has **Open on GitHub**, which opens a pre-filled new issue in your browser (public, under your own GitHub account and GitHub's terms), **Copy report**, which only copies the text to your clipboard, and **Email instead**, which opens your email app with a message to quki-notes@skvfx.com. Email is the private route: use it for anything you don't want public. The email is handled by your email provider and read by the developer.

**What reports are used for.** Reports are used only to fix problems and answer requests. They are never used for marketing, profiling or selling anything.

### The failure log on your device

QuKi Notes keeps a short log of things that went wrong, such as a failed save, a storage error or a crash. It lives only on your device: in the app's own storage, outside your QuKi folder (in your browser's storage for the web version). An entry holds the time, what kind of failure it was, which operation was running, the type and code of the error, the app version, the platform and the storage type. It does not hold the text of your QuKis or their file names. It is capped in size and the oldest entries are dropped. It is never sent anywhere on its own. You can read, copy and clear it in Settings under **Diagnostics**. It goes into a report only if you tick **Include recent log** in the report form, and then you see it, and can edit it, before anything is sent.

## Device backups

On Android, if you use app storage and your device's backup is turned on, Android may include your QuKis in its device backup. That backup is handled by Android and Google under your device settings, not by QuKi Notes. QuKis in filesystem storage (`Documents/QuKi_Notes`) are covered by whatever backup or sync you use for that folder.

## Analytics, crash reporting, and telemetry

None. This is a current design decision. The failure log stays on your device, and a report is sent only when you choose to send it.

## Permissions

QuKi Notes requests only the permissions it needs to function on each platform. On Android that means internet access (for web images, links and the problem reports you choose to send) and, only if you choose filesystem storage, **All files access**, so it can keep your QuKis in your `Documents` folder. It does not request location, contacts, microphone, camera, or any other sensitive permission.

## Third parties

QuKi Notes does not share data with any third party. There are no advertising SDKs, analytics SDKs, or crash-reporting SDKs in the app. The only data that can leave the app because of something you do inside it is a problem report you send, which passes through the relay and Cloudflare and ends up on GitHub as described above.

## Children

QuKi Notes does not knowingly collect information from anyone. It collects no information from anyone, regardless of age.

## Changes to this policy

If anything here ever changes, the updated policy will be posted at this URL with a new effective date, and the change will be listed in the [policy history](#policy-history) at the end of this page. The core commitment — no automatic data collection — is not subject to change.

## Contact

Questions? Email quki-notes@skvfx.com (private), open an issue on [GitHub](https://github.com/ScottKirvan/QuKi-Notes/issues) (public) or reach out on [Discord](https://discord.gg/TN6XJSNK5Y).

## Policy history

Every change to this policy, newest first. The version is the first QuKi Notes release that included the change.

| Date | Version | Change |
|---|---|---|
| 2026-11-26 | v0.27.0 | Adds in-app problem reporting: a report you send goes through a small relay server and becomes a public GitHub issue, or you can email it. Adds the failure log kept on your device. "No servers" is replaced by an exact description of the relay, and the commitment is now "no automatic data collection". Still no analytics, telemetry or tracking. |
| 2026-10-11 | v0.26.0 | Lists the spell-check dictionary download made by the Linux desktop app. |
| 2026-10-11 | v0.26.0 | The web version is hosted on Cloudflare, not GitHub Pages. |
| 2026-09-26 | v0.25.0 | Rewritten for the new app: QuKis are plain files rather than a database. Covers images, settings, Send on each platform, web images, the web version and the command-line tools. The analytics section now calls "no analytics" a current design decision instead of a permanent one. |
| 2026-06-29 | v0.14.1 | Updated the Discord contact link. |
| 2026-06-25 | v0.13.1 | App name written as "QuKi Notes"; no change in meaning. |
| 2026-06-05 | v0.9.2 | First published. |
