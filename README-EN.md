# 1Password Extension — Manifest V3 Migration

[中文版 / Chinese version](README.md)

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

## Desktop Fix: "Browser's runtime signature invalid (103)"

After installing the extension, the 1Password 6 desktop app may reject the browser connection and the extension console shows:

```
[AGENT:NM] Unrecoverable state: Browser's runtime signature invalid (103)
```

This is **not an extension bug**. The 1Password 6 desktop app validates the running Chrome process's code signature against a hard-coded whitelist from 2018 that only accepts the `Developer ID Application: Google, Inc. (EQHXZ8M8AV)` certificate. Modern Chrome is signed by `Google LLC (EQHXZ8M8AV)`, so the check fails on the desktop side.

`fix-1password6.sh` fixes this by patching the desktop app's `OnePasswordCore.framework`:

- Replaces the certificate name in 2 hard-coded requirement strings (`Google, Inc.` → `Google LLC`), **keeping signature verification enabled** (only Google LLC-signed Chrome is accepted)
- Verifies the patched requirement parses and that the locally installed Chrome satisfies it (`SecStaticCodeCheckValidityWithErrors`)
- Re-signs **only** `OnePasswordCore.framework` (ad-hoc by default). Nothing else in the app bundle is touched.

### Usage

```bash
# Quit 1Password and 1Password mini (menu bar) first
bash fix-1password6.sh
```

Interactive 3-step flow:

1. **Language selection** — `1` for 中文, `2` for English, Enter for auto-detect
2. **Procedure + environment checks** (read-only) — review, then confirm to continue
3. **Final execution confirmation** — then it backs up, patches, verifies, and re-signs

Options:

```bash
bash fix-1password6.sh "MyCertName"   # sign with a keychain cert instead of ad-hoc
bash fix-1password6.sh --lang=zh      # skip the language prompt
```

The script aborts safely on unrecognized binary builds and prints the exact rollback command on success.

### Important notes

- **Never `codesign --deep` the whole app bundle** after patching. Re-signing the login item `2BUA8C4S2C.com.agilebits.onepassword4-helper` (which *is* 1Password mini) breaks its Background Task Management registration on macOS 13+; launchd then refuses to spawn it and the extension fails with "1Password failed to connect to 1Password mini". Only the framework should be re-signed.
- If mini stops spawning after unrelated signature changes: `sudo sfltool resetbtm`, reboot, then relaunch 1Password.

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
