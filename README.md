# Jellyfin Open File Location

A Tampermonkey userscript + small Windows helper that adds **Open file location** to Jellyfin Web's three-dot item menu.

It reads the filesystem path Jellyfin already knows for the selected media item and opens that location on the Windows PC running the browser.

- **Directory Opus is preferred automatically** when installed.
- **Windows Explorer is used as a fallback.**
- For files, Directory Opus opens the parent folder and selects the media file.
- No video/audio data is downloaded or re-encoded.
- Normal use is silent: the default VBS helper does not flash a PowerShell window.

> [!NOTE]
> This is a personal utility and is not an official Jellyfin or Directory Opus project.

## Install

### 1. Install the Windows helper

[**Download the repository as a ZIP**](https://github.com/juliekeygen-netizen/Jellyfin-Open-File-Location-Tampermonkey/archive/refs/heads/main.zip), extract it, then run:

```text
INSTALL.cmd
```

The installer registers the local `jellyopen-*://` protocol handlers for the current Windows user and copies the helper scripts to:

```text
%LOCALAPPDATA%\JellyfinOpenLocation
```

Administrator rights are not required.

### 2. Install the Tampermonkey userscript

You need the [Tampermonkey](https://www.tampermonkey.net/) browser extension.

[**Install / download Jellyfin-Open-File-Location.user.js**](https://raw.githubusercontent.com/juliekeygen-netizen/Jellyfin-Open-File-Location-Tampermonkey/main/Jellyfin-Open-File-Location.user.js)

Tampermonkey should recognize the `.user.js` link and show its installation page. If your browser displays the source instead, copy it into a new Tampermonkey script and save it.

The userscript also contains `@downloadURL` and `@updateURL` entries pointing back to this repository, so this GitHub copy is the canonical script source.

### 3. Reload Jellyfin

Open Jellyfin Web, click the **⋮** menu on a movie/episode/item, then choose:

```text
Open file location
```

With the default configuration it will:

1. Ask Jellyfin for the item's `Path`.
2. Encode the path and pass it to a local `jellyopen-vbs://` protocol.
3. Use Directory Opus if `DOpusRT.exe` is detected.
4. Otherwise open the item in Windows Explorer.

## How it works

The browser is not allowed to directly execute `explorer.exe` or control Directory Opus. The project therefore has two parts.

### Userscript

`Jellyfin-Open-File-Location.user.js` injects a custom row into Jellyfin's item action sheet.

The row is intentionally **not** a Jellyfin command element: it does not use Jellyfin's `.actionSheetMenuItem`, `.itemAction`, `data-id`, or `data-action` semantics. This avoids accidentally triggering Jellyfin playback/navigation handlers.

When clicked, it uses Jellyfin's page `ApiClient` to fetch the selected item's filesystem path and launches a local custom protocol through a hidden iframe so Jellyfin's own URL/history is not changed.

### Windows helper

`INSTALL.cmd` runs `Install-JellyfinOpenLocation.ps1`, which installs the handlers for:

```text
jellyopen-vbs://
jellyopen-ps://
jellyopen-psdebug://
```

The default `jellyopen-vbs://` handler runs invisibly through Windows Script Host.

For Directory Opus, the helper uses `DOpusRT.exe` to:

1. Navigate to the media file's parent directory.
2. Select the exact filename.
3. Scroll it into view.

If Directory Opus cannot be found and `fileManager` is set to `auto`, it falls back to Windows Explorer.

## Configuration

The easy settings are near the top of `Jellyfin-Open-File-Location.user.js`:

```js
const CONFIG = {
    menuPosition: 'last',
    fileManager: 'auto',
    helperMode: 'vbs',
    protocolLaunch: 'iframe',
    closeMenuAfterOpen: false,
    debugLog: false
};
```

### `menuPosition`

```js
menuPosition: 'last'
```

Places **Open file location** after the last normal Jellyfin menu command.

You can also use a 1-based number:

```js
menuPosition: 1
menuPosition: 4
menuPosition: 6
```

Divider lines are not counted.

### `fileManager`

```js
fileManager: 'auto'
```

Prefer Directory Opus, otherwise Explorer.

```js
fileManager: 'dopus'
```

Require Directory Opus. An error is shown if it cannot be found.

```js
fileManager: 'explorer'
```

Always use Windows Explorer.

### `helperMode`

```js
helperMode: 'vbs'
```

Default. Invisible Windows Script Host helper with no terminal flash.

```js
helperMode: 'powershell'
```

Use the PowerShell helper in hidden mode.

```js
helperMode: 'powershell-debug'
```

Open a visible PowerShell window and keep it open, useful for troubleshooting.

### `protocolLaunch`

```js
protocolLaunch: 'iframe'
```

Default and recommended. The custom protocol is opened through a hidden iframe, leaving Jellyfin's top-level URL untouched.

```js
protocolLaunch: 'location'
```

Fallback if a browser refuses custom protocols from an iframe.

### `closeMenuAfterOpen`

```js
closeMenuAfterOpen: false
```

Default and safest. Jellyfin's three-dot menu stays open after the file manager launches; click outside it when returning to Jellyfin.

Setting it to `true` asks Jellyfin to close the menu automatically.

## Requirements

- Windows 10/11 for the local helper.
- Jellyfin Web in a browser supported by Tampermonkey.
- Tampermonkey.
- Optional: Directory Opus. Explorer is supported without it.
- The path reported by Jellyfin must also exist on the Windows machine running the browser.

Examples that work:

```text
D:\Media\Movies\Movie.mkv
\\server\share\Movies\Movie.mkv
```

A server-only Linux path such as `/media/movies/Movie.mkv` cannot be opened directly on an unrelated Windows client unless you add your own path mapping.

## Files

| File | Purpose |
|---|---|
| `Jellyfin-Open-File-Location.user.js` | Tampermonkey/Jellyfin UI integration |
| `JellyOpenHandler.vbs` | Default invisible Windows protocol handler |
| `JellyOpenHandler.ps1` | PowerShell handler + debug mode |
| `Install-JellyfinOpenLocation.ps1` | Installs helper files and protocol registrations |
| `Uninstall-JellyfinOpenLocation.ps1` | Removes helper files and protocol registrations |
| `INSTALL.cmd` | Easy installer launcher |
| `UNINSTALL.cmd` | Easy uninstaller launcher |

## Uninstall

Run:

```text
UNINSTALL.cmd
```

Then disable or remove **Jellyfin - Open file location** from Tampermonkey.

## Security notes

The local handlers only accept absolute Windows drive paths (`C:\...`) or UNC paths (`\\server\share\...`) and verify that the target exists before opening it.

The userscript does not send the media path to an external service. The path is transferred locally from the Jellyfin page to the registered Windows protocol handler.

## Current version

**v0.5.1** — adds repository-backed Tampermonkey download/update metadata to the stable v0.5 userscript.
