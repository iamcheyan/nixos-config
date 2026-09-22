# Marketplace Submission Guide: Active Window

This document contains pre-flight checks and submission templates for submitting `iamcheyan.active-window` to the [Omarchy Plugin Marketplace](https://github.com/omacom/omarchy-plugin-marketplace).

---

## 1. Pre-Flight Checklist

- [x] **Repository is public & root-mapped**: `manifest.json` is at repository root.
- [x] **Valid manifest.json**: `schemaVersion: 1`, ID `iamcheyan.active-window`, no `omarchy.*` prefix. Passes `omarchy plugin validate .`.
- [x] **Complete documentation**: Tri-lingual README (English, 中文说明, 日本語) with installation, configuration, uninstallation, dependencies, and license.
- [x] **LICENSE file**: MIT License included in root directory.
- [x] **Preview asset**: `preview.png` present in root directory, non-interlaced RGB PNG.
- [x] **Clean install/uninstall**: Pure informational widget; does not write to system directories, add daemon services, or overwrite user files.
- [x] **Automated Security Baseline**:
  - Zero `pkexec` / `sudo` / `systemctl` / shell invocations.
  - Native file reading via `Quickshell.Io.FileView` with read-only access to `/etc/os-release`.
  - All external text (window titles, app names) rendered via `Text.PlainText` to prevent rich-text / HTML injection.

---

## 2. Submission Issue Template

Use the following metadata when submitting via the web form or GitHub CLI:

- **Issue Title**: `[Plugin]: Active Window`
- **Repository URL**: `https://github.com/iamcheyan/omarchy-active-window`
- **Category**: `Desktop`
- **Tags**: `bar, quickshell`

### Web Form Submission

Open: [Submit a plugin on GitHub Marketplace](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml)

### GitHub CLI (`gh`) Submission

```bash
cat <<'SUBMIT_EOF' > /tmp/submit-active-window.md
### Repository URL

https://github.com/iamcheyan/omarchy-active-window

### Category

Desktop

### Tags

bar, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Initial submission of Active Window bar widget for Omarchy Quattro. Displays focused window title and icon, or distribution logo and version on empty desktop.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
SUBMIT_EOF

gh issue create \
  --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: Active Window" \
  --body-file /tmp/submit-active-window.md
```
