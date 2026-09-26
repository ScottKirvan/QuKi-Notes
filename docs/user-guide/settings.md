# Settings

Open Settings with the **gear** button in the editor's top bar, or the same button in the QuKis list.

## Appearance

**Theme** follows your system's light or dark setting, and switches automatically when that changes. There's no manual toggle.

## Storage

**Android, Windows and Linux** show where your QuKis are stored:

- **Filesystem storage**, followed by the folder's path.
- **App storage (private)**, with the warning "Files will be removed on uninstall. Change location."

Tap **Change location** to open the same choice you saw on first launch. Tap the back arrow on that screen to leave things as they are.

Changing the location doesn't move anything. Your existing QuKis, Trash and images stay in the old folder, and QuKi Notes starts using the new one straight away with a blank editor. To bring QuKis along, move or copy the files yourself, including the hidden `.meta` and `.trash` folders and the `media` folder, while QuKi Notes is closed.

::: warning
On Windows and Linux, "App storage" is the `Documents/qukis` folder. It's an ordinary folder, not private to the app, and it isn't removed on uninstall, even though Settings shows the uninstall warning.
:::

::: info
On Android, if QuKi Notes picked up your QuKis from an earlier version that kept them in its private storage, Settings shows that location as **Filesystem storage** with a path, and no uninstall warning. Those files are still private to the app and would still be removed on uninstall. Use **Change location** → **Filesystem storage** if you want them in `Documents`, and move the files across.
:::

**Web** shows a note instead:

> QuKis are stored in this browser, not in a folder you choose. Clearing this site's browser data will delete them.

QuKis in the web version stay in that one browser on that one device. There's currently no way to export them or move them to the desktop or Android app, apart from copying each QuKi's text by hand. On iPhone and iPad, Safari can clear a website's storage by itself if the site isn't used for a while. Adding QuKi Notes to your home screen makes that much less likely.

## Notes

**Trash** opens the Trash screen. See [QuKis List → Trash](/user-guide/qukis-list#trash).

## About

Shows the app's name and version. Tap **Version** to copy the version number to the clipboard.

## Help

The **?** button in the editor and the QuKis list opens the Help dialog. It shows the version, plus the branch and date that build was made from. Tap them to copy all three, handy for bug reports. It also has links to:

- **Documentation**: this site
- **Discord**: chat with other users and get help
- **GitHub**: source code, issues and release notes
- **Buy me a coffee**: support the project

Press **Escape**, tap outside the dialog, or tap **Close** to dismiss it.
