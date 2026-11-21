<table>
  <tr>
    <td width="110"><img src="logo.png" width="96" alt="OldTroll"></td>
    <td><h1>OldTroll</h1><p><strong>One-tap IPA installer for legacy iOS devices (armv7, iOS 6–10).</strong></p></td>
  </tr>
</table>

OldTroll brings TrollStore-like functionality to older, jailbroken iOS devices. It allows you to install any IPA file with a single tap — no computer, no signing service, no App Store restrictions.

---

## Features

- 📦 **Install any IPA** — sideload apps without a computer
- 🔓 **Signature bypass** — converts IPAs into signature-bypassed debs on-device
- 📥 **Install from URL** — download and install directly from a link
- 🔗 **URL Scheme support** — trigger installs from Safari or other apps
- 🧹 **Cache cleaner** — clear temporary build files
- 🔄 **Respring** — restart SpringBoard from within the app
- 📱 **iPad & iPhone** — supports both portrait and landscape on iPad
- ⚡ **Lightweight** — tiny package, fast installation

---



## Usage

### Install an IPA File

1. Open **OldTroll**
2. Tap the **+** button in the top-right corner
3. Select **Install IPA File**
4. Choose an `.ipa` file from the built-in file browser (starts at root `/`)
5. Wait for the progress bar (`Config IPA...`)
6. Review the app details (icon, name, version, bundle ID)
7. Tap **Install**

### Install from URL

1. Tap the **+** button
2. Select **Install from URL**
3. Paste the direct download link to an IPA file
4. Tap **Install** — the app will download (with progress bar) then install automatically

### Manage Installed Apps

- The **Apps** tab shows only apps installed via OldTroll
- Tap any app to view details
- Use **Open** to launch the app
- Use **Uninstall** to remove it

---

## URL Scheme

OldTroll supports two URL schemes for triggering IPA installations from Safari or other apps:

```
apple-magnifier://install?url=<URL_to_IPA>
cor-oldtroll://install?url=<URL_to_IPA>
```

**Example:**
```
cor-oldtroll://install?url=https://example.com/app.ipa
```

**To enable:** Go to **Settings → External URL Call** and toggle it on.

---

## How It Works

OldTroll converts IPA files into **signature-bypassed deb packages** directly on the device:

1. **Extract** the IPA and read its Info.plist (bundle ID, version, icon)
2. **Pseudo-sign** the binary with `ldid` (adhoc signature + entitlements)
3. **Package** everything into a Cydia-compatible `.deb`
4. **Install** the deb via `dpkg` (using a setuid helper for root privileges)
5. **Refresh** the icon cache with `uicache`

> **Note:** OldTroll requires a **rootful jailbreak**. If the jailbreak is removed or expires, apps installed via OldTroll will no longer open — just like any other jailbreak-dependent software.

---

## Settings

| Option | Description |
|--------|-------------|
| **External URL Call** | Enable/disable URL scheme integration |
| **Clear Cache** | Remove temporary IPA build files from `/tmp` |
| **Respring** | Restart SpringBoard |
| **Donate** | Support the developer |

---


## Troubleshooting

**App crashes on launch?**
- Ensure your device is armv7 (32-bit). OldTroll does not support 64-bit devices.
- Reinstall the deb package.

**"Installation failed — superuser privilege"?**
- The `oldtroll_helper` binary may have lost its setuid bit. Reinstall OldTroll.

**Installed app not showing on home screen?**
- Run `uicache` in terminal, or tap **Respring** in Settings.

**Cydia shows default icon for installed IPA?**
- OldTroll automatically extracts the app's icon and sets it as the Cydia package icon. If it doesn't appear, refresh Cydia.

---

*Made with ❤️ for legacy iOS devices.*
