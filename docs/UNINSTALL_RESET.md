# Uninstall And Reset

Ouro MD stores documents wherever you put them. Removing the app or preferences
does not delete your markdown files.

## Uninstall The App

Quit Ouro MD, then remove the installed bundle:

```sh
rm -rf "/Applications/Ouro MD.app"
```

If you installed to your user Applications folder:

```sh
rm -rf "$HOME/Applications/Ouro MD.app"
```

## Reset Preferences

This clears theme, sidebar, autosave, autopair, zoom, telemetry opt-in/out, the
anonymous telemetry install id, and update-check preferences.

```sh
defaults delete bot.ouro.md
```

It is normal for `defaults` to print an error if there are no preferences yet.

## Remove Custom Themes

Custom CSS themes live here:

```sh
rm -rf "$HOME/Library/Application Support/ouro-md"
```

Only remove this directory if you no longer need local theme files.

## Clear Open Recent

Inside the app, use **File -> Open Recent -> Clear Menu**.

macOS stores recent-document state outside Ouro MD's own markdown files. Clearing
the menu does not delete the documents themselves.

## Full Local Reset

This removes the app, preferences, and custom theme support files:

```sh
rm -rf "/Applications/Ouro MD.app"
rm -rf "$HOME/Applications/Ouro MD.app"
defaults delete bot.ouro.md 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/ouro-md"
```

Your markdown documents remain wherever they were saved.
