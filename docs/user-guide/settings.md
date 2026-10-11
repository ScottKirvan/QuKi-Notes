# Settings

Open Settings with the <i-lucide-settings /> **gear** button in the editor's top bar, or the same button in the QuKis list.

## Appearance

**Theme** follows your system's light or dark setting, and switches automatically when that changes. There's no manual toggle.

**Text size** sets how big the text in the editor is: **Small**, **Normal** (the default), **Large** or **Extra large**. The change shows as soon as you go back to the editor, and QuKi Notes remembers it next time. Headings, list indentation and quotes grow and shrink with it. It changes the editor only, not the QuKis list or the menus.

## Storage

**Android, Windows and Linux** show where your QuKis are stored:

- **Filesystem storage**, followed by the folder's path. This is what Windows and Linux always show, including when you chose **Use app storage** (that's just a `qukis` folder in your Documents folder). Uninstalling QuKi Notes leaves it in place.
- **App storage (private)**, with the warning "Files will be removed on uninstall. Change location." Only Android shows this, when you chose **Use app storage** there: Android keeps those QuKis in the app's private storage, which is deleted when you uninstall.

Tap **Change location** to open the same choice you saw on first launch. Tap the back arrow on that screen to leave things as they are.

Changing the location doesn't move anything. Your existing QuKis, Trash and images stay in the old folder, and QuKi Notes starts using the new one straight away with a blank editor. To bring QuKis along, move or copy the files yourself, including the hidden `.meta` and `.trash` folders and the `media` folder, while QuKi Notes is closed.

**Web** shows a note instead:

> QuKis are stored in this browser, not in a folder you choose. Clearing this site's browser data will delete them.

QuKis in the web version stay in that one browser on that one device. To keep a copy or take them elsewhere, use **Export**. On iPhone and iPad, Safari can clear a website's storage by itself if the site isn't used for a while. Adding QuKi Notes to your home screen makes that much less likely.

**Export**, on every platform including the web, saves your whole library as one `.tar.gz` archive: every QuKi, everything in Trash, QuKi Notes' records of when each was created and trashed, the `media` folder and the `.quki` settings folder. Extracting it gives you a folder QuKi Notes can open as-is. Where the archive goes depends on the platform:

- **Windows and Linux**: you choose where to save it.
- **Android**: it's saved in your QuKi folder, and a message shows where.
- **Web**: your browser downloads it, named `quki-export-` followed by the date and time.

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
