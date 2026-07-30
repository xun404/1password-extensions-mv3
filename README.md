# 1Password Extension — Manifest V3 Migration

Unofficial Manifest V3 port of the 1Password Chrome extension v4.7.5.90, the last version compatible with the **1Password 6** desktop client.

## Why This Exists

- Chrome has fully deprecated Manifest V2 extensions, disabling them with the message *"This extension is no longer supported"*
- Official 1Password extensions (v7+) dropped support for the 1Password 6 desktop client and its local vault format
- This migration patches the original MV2 extension to load as a Manifest V3 extension, preserving compatibility with 1Password 6

## What Changed

| File | Change |
|------|--------|
| `manifest.json` | MV2 → MV3: `service_worker`, `action`, `host_permissions` |
| `background-wrapper.js` | Polyfills `window`, `browserAction`→`action`, strips `webRequestBlocking` |
| `global.min.js` | Patched `contextMenus.create` to include `id` and use `onClicked` (required by MV3 service workers) |

## Known Issues

- **Go & Fill redirect** — The `webRequest.onBeforeRequest` redirect feature no longer works (MV3 removed `webRequestBlocking`). Core form-filling and native messaging remain functional.
- **Service Worker lifecycle** — The background worker may be terminated by Chrome when idle. The native messaging connection re-establishes on wake.
- **Enhanced Safe Browsing** — Chrome flags this as untrusted because the extension files have been modified from their original Web Store hashes. This is cosmetic only.
- **No future updates** — This is a static patch. No new features, no security fixes beyond what was in v4.7.5.90.
- **Use at your own risk** — This is unofficial, unsupported, and not endorsed by AgileBits.

## Manual Installation

1. Download the latest release `.zip` from the [Releases](https://github.com/xun404/1password-extensions-mv3/releases) page
2. Extract the zip to a permanent folder on your computer
3. Open Chrome and navigate to `chrome://extensions`
4. Enable **Developer mode** (toggle in the top-right corner)
5. Click **Load unpacked** and select the extracted folder
6. The 1Password extension icon should appear in your toolbar

> **Important**: The extension folder must remain on your disk permanently. Do not delete it after loading, or the extension will stop working.

### Updating

Download the latest release, overwrite the files in your extension folder, then click the refresh icon on the extension card in `chrome://extensions`.

## Building a Release

```bash
git tag v4.7.5.91
git push origin v4.7.5.91
```

A GitHub Action packages the extension and creates a release automatically.

## License / Attribution

The original 1Password extension is proprietary software owned by **AgileBits, Inc.** See [LICENSE.md](LICENSE.md) for full attribution.

This repository exists solely for archival and compatibility purposes.
