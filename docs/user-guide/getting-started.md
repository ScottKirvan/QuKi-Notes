# Getting Started

## What is QuKi Notes?

QuKi Notes is a scratchpad and pasteboard: a blank canvas when you open it. Type a thought, draft a message, jot a list, dump a link. Use the content right there, send it somewhere, or let it drift down the list as newer things arrive. There's no vault, no folder structure, no organization ritual.

Each QuKi is a plain markdown (`.md`) file.

## Download and Install QuKi Notes

All the latest versions can be found on the [Downloads](/downloads) page.

:::tabs

== Android

Join our test group to download QuKi Notes on Google Play, or [sideload](https://en.wikipedia.org/wiki/Sideloading) the APK directly.  See [Get QuKi Notes for Android](/install/android) for the details

== macOS, iPhone and iPad

There's no native app for Apple devices yet, but the web app works in Safari.

1. Open [qukinotes.scottkirvan.com](https://qukinotes.scottkirvan.com/) in Safari.
2. To keep it like an app:
   - **iPhone and iPad**: tap **Share**, then **Add to Home Screen**.
   - **Mac**: choose **File → Add to Dock**.


== Windows

1. Open the [Downloads](/downloads) page.
2. Under **Windows**, click **Installer**.
3. Open the downloaded `.exe` file.
4. Follow the installer. You can pick the install folder, and choose whether to add the optional **Command-line tools**, which add the `quki` and `quki-mcp` commands (see [Command Line & MCP](/command-line/)).

== Linux

QuKi Notes for Linux comes as an AppImage or a Debian package, each for x64 and ARM64 (AArch64) machines.

#### AppImage

1. Open the [Downloads](/downloads) page.
2. Under **Linux**, click **AppImage**, or **AppImage (AArch64, ARM64)** on an ARM machine.
3. Make the downloaded file executable, then run it:

   ```bash
   chmod +x QuKi-Notes-x64.AppImage
   ./QuKi-Notes-x64.AppImage
   ```

   On ARM the file is `QuKi-Notes-arm64.AppImage`.

There's nothing to install. The command-line tools are included in the AppImage; see [Command Line & MCP](/command-line/) to link them.

#### Debian package

For Debian, Ubuntu and other distributions that use `.deb` packages.

1. Open the [Downloads](/downloads) page.
2. Under **Linux**, click **Debian Package**, or **Debian Package (AArch64, ARM64)** on an ARM machine.
3. In a terminal, go to the folder you downloaded it to and install it:

   ```bash
   sudo apt install ./quki-notes-linux-x64-*.deb
   ```

   On ARM the file name starts with `quki-notes-linux-arm64-`.

The package also installs the `quki` and `quki-mcp` commands (see [Command Line & MCP](/command-line/)).




== Web browser and ChromeOS

This is also the way to use QuKi Notes on ChromeOS.

1. Open [qukinotes.scottkirvan.com](https://qukinotes.scottkirvan.com/).
2. Optionally, install it as an app from your browser (in Chrome and Edge, the install icon in the address bar). It then gets its own window and icon, and works offline.

:::
## First launch

On Android, Windows and Linux, the first launch asks where your QuKis should live. This screen appears once. You can change the location later in **Settings → Storage**.

**Windows and Linux**

- **Choose a folder**: pick any folder. QuKis are saved there as plain `.md` files you can open, back up or sync with anything you like.
- **Use app storage**: QuKis go in a `qukis` folder inside your Documents folder.


**Android**

- **Filesystem storage (recommended)**: QuKis are saved in `Documents/QuKi_Notes` on your device, where any file manager can see them. They survive uninstalling the app. QuKi Notes needs Android's **All files access** permission for this. If it isn't granted yet, you'll see a short explanation and a **Grant access** button that opens the system settings page. Turn the permission on, then switch back to QuKi Notes.
- **Use app storage**: QuKis are kept in the app's private storage. No other app can see them, and they're removed if you uninstall. Settings shows a warning while this is in use.

**Web**

There's no setup screen. QuKis are stored in your browser's private storage for this site. They're only in that browser, on that device, and clearing the site's data deletes them. See [Settings](/user-guide/settings#storage) for what that means in practice.

After this, the editor opens: blank, ready for typing.

**If QuKi Notes already has your QuKis**

If you used an earlier version of QuKi Notes on the same device, the first launch picks up the folder it was using and goes straight to the editor, without asking. Nothing in the folder is renamed or converted.

**If your folder isn't reachable**

If the folder you chose can't be found at launch (an unplugged drive, a disconnected network share), QuKi Notes says so instead of opening an empty editor. You can pick a different location, or go back, which closes the app so you can reconnect the folder and try again.

## Every launch

QuKi Notes always opens to a new, blank QuKi. Your earlier QuKis are one tap away in the QuKis list.

Your QuKi saves automatically as you type. When you're done, send it somewhere or just leave it; it'll be in the list next time.

## Navigation at a glance

The editor is home. It doesn't have a back button.

The editor's top bar, left to right:

| Button                                 | What it does                                                                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| <i-lucide-file-stack /> **QuKis** (far left) | Opens your QuKis list. Greyed out until you start typing your first QuKi.                                                    |
| <i-lucide-book-open /> <i-custom-markdown-mark /> <i-lucide-code-xml /> **Mode** | While editing, switches between the rendered view and plain text; while reading, brings editing back. See [Capturing QuKis](/user-guide/capturing-qukis#plain-text-mode). |
| <i-lucide-plus /> **New QuKi** | Starts a new, blank QuKi                                                                                               |
| <i-lucide-circle-help /> **Help** | Help: version, documentation, Discord, GitHub and support links                                                        |
| <i-lucide-send /> **Send** | Sends the QuKi. See [Sending QuKis](/user-guide/sending-qukis).                                                        |
| <i-lucide-settings /> **Settings** | Opens Settings                                                                                                         |
| <i-lucide-trash-2 /> **Delete** (red, far right) | Moves the current QuKi to Trash. Greyed out until the QuKi has been saved at least once.                               |

### Going back on Android

On Android, the system Back (swipe in from the edge of the screen, or the Back button) takes you back through where you've been:

- If a dialog is open, Back closes it, the same as tapping Cancel or Close.
- Otherwise it steps back through the QuKis you've opened or started and the QuKis list, in the order you visited them. Starting a new QuKi and pressing Back takes you to the QuKi you were in before.
- A QuKi you come back to opens for reading, scrolled to where you left it.
- Settings and Trash are never stops. Back from either takes you to wherever you were before you opened them.
- A QuKi you've deleted since is skipped. So is a new QuKi you never typed anything into.
- Pressing Back on the first place you visited closes the app.

Your path is forgotten when the app closes. Each launch starts fresh.
