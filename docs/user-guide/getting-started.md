# Getting Started

## What is QuKi Notes?

QuKi Notes is a scratchpad and pasteboard: a blank canvas when you open it. Type a thought, draft a message, jot a list, dump a link. Use the content right there, send it somewhere, or let it drift down the list as newer things arrive. There's no vault, no folder structure, no organization ritual.

Each QuKi is a plain markdown (`.md`) file.

## Platforms

| Platform | How you get it |
|---|---|
| Android | Google Play (closed testing). See [Get QuKi Notes for Android](/install/android). |
| Windows | Installer (`.exe`) from [Downloads](/downloads) |
| Linux | AppImage from [Downloads](/downloads) |
| Web browser | [www.scottkirvan.com/QuKi-Notes/app](https://www.scottkirvan.com/QuKi-Notes/app/) |

There's no native iOS or macOS app yet.

## Installation

- **Android**: install from Google Play once you've joined the test group. The [Android install page](/install/android) walks through it.
- **Windows**: run the installer. It lets you pick the install folder. It also has an optional **Command-line tools** component, which adds the `quki` and `quki-mcp` commands (see [Command Line & MCP](/command-line/)).
- **Linux**: download the AppImage, make it executable (`chmod +x QuKi-Notes.AppImage`), and run it. There's nothing to install. The command-line tools are included in the AppImage; see [Command Line & MCP](/command-line/) to link them.
- **Web**: open the address above. Your browser may offer to install it as an app, which gives it its own window and home-screen icon and lets it work offline.

## First launch

On Android, Windows and Linux, the first launch asks where your QuKis should live. This screen appears once. You can change the location later in **Settings → Storage**.

**Windows and Linux**

- **Choose a folder**: pick any folder. QuKis are saved there as plain `.md` files you can open, back up or sync with anything you like.
- **Use app storage**: QuKis go in a `qukis` folder inside your Documents folder.


**Android**

- **Filesystem storage (recommended)**: QuKis are saved in `Documents/QuKi_Notes` on your device, where any file manager can see them. They survive uninstalling the app. QuKi Notes needs Android's **All files access** permission for this. If it isn't granted yet, you'll see a short explanation and a **Grant access** button that opens the system settings page. Turn the permission on, then switch back to QuKi Notes.
- **Use app storage**: QuKis are kept in the app's private storage. No other app can see them, and they're removed if you uninstall. Settings shows a warning while this is in use.

::: warning
On the Android permission screen there's no way back to the storage choice. If you tap **Filesystem storage** and then decide not to grant All files access, close the app. On the next launch, you'll be asked again and can pick **Use app storage** instead.
:::

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

| Button | What it does |
|---|---|
| **QuKis** (stacked pages, far left) | Opens your QuKis list. Greyed out until you have at least one QuKi. |
| **Mode** (book, markdown or code icon) | Switches between the rendered view and plain text. See [Capturing QuKis](/user-guide/capturing-qukis#plain-text-mode). |
| **+** | Starts a new, blank QuKi |
| **?** | Help: version, documentation, Discord, GitHub and support links |
| **Send** (paper plane) | Sends the QuKi. See [Sending QuKis](/user-guide/sending-qukis). |
| **Settings** (gear) | Opens Settings |
| **Delete** (red trash can, far right) | Moves the current QuKi to Trash. Greyed out until the QuKi has been saved at least once. |
