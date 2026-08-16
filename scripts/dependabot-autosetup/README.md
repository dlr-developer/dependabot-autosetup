# dependabot-autosetup

![Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-active-brightgreen)

A single script that sets up [Dependabot](https://github.com/dependabot) on any repo -- detects your package ecosystem(s), writes the config, configures auto-merge for low/high-risk updates on your terms, and manages security alerts and repo visibility. Re-run it any time to check status and change settings.

> **Not affiliated with GitHub or Dependabot.** This is an independent tool that automates the setup of GitHub's own [Dependabot](https://github.com/dependabot) feature -- it doesn't modify or replace it.

---

## 🚀 Install

### Option 1: Curl install (any terminal)

Pick the command for whichever terminal you're already in -- `cd` into your project folder first, then paste it.

**Git Bash / macOS / Linux:**

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/dlr-developer/dependabot-autosetup/main/scripts/dependabot-autosetup/install-dependabot-autosetup.sh | bash
```

**PowerShell:**

```powershell
cd your-project
$bash = "$env:ProgramFiles\Git\bin\bash.exe"; if (!(Test-Path $bash)) { $bash = "${env:ProgramFiles(x86)}\Git\bin\bash.exe" }; & $bash -c "curl -fsSL https://raw.githubusercontent.com/dlr-developer/dependabot-autosetup/main/scripts/dependabot-autosetup/install-dependabot-autosetup.sh | bash"
```

**Command Prompt (cmd.exe):**

```cmd
cd your-project
"%ProgramFiles%\Git\bin\bash.exe" -c "curl -fsSL https://raw.githubusercontent.com/dlr-developer/dependabot-autosetup/main/scripts/dependabot-autosetup/install-dependabot-autosetup.sh | bash"
```

All three do the same thing -- PowerShell and cmd just hand the work to Git's own `bash.exe` directly instead of trying to understand `curl | bash` themselves, since that's bash syntax. All of them require [Git for Windows](https://git-scm.com/download/win) to be installed (Mac/Linux already have bash built in).

This installs all five files -- `dependabot-autosetup.sh`, `dependabot-autosetup.bat`, `install-dependabot-autosetup.sh`, `README.md`, and `unblock-screenshot-windows.png` -- into `./scripts/dependabot-autosetup`, nested in its own folder so it never collides with other scripts already in your project's `scripts/` folder.

**It then launches the tool automatically** -- no second command needed. If you're in a non-interactive context where that's not possible (CI, automation, etc.), it skips straight to printing the manual command instead. To run it yourself later (or if auto-launch was skipped):

**Git Bash / macOS / Linux:**

```bash
./scripts/dependabot-autosetup/dependabot-autosetup.sh
```

**PowerShell:**

```powershell
$bash = "$env:ProgramFiles\Git\bin\bash.exe"; if (!(Test-Path $bash)) { $bash = "${env:ProgramFiles(x86)}\Git\bin\bash.exe" }; & $bash scripts/dependabot-autosetup/dependabot-autosetup.sh
```

**Command Prompt (cmd.exe):**

```cmd
"%ProgramFiles%\Git\bin\bash.exe" scripts\dependabot-autosetup\dependabot-autosetup.sh
```

### Option 2: Windows double-click

1. Download `dependabot-autosetup.bat` and `dependabot-autosetup.sh` from this repo into a `scripts/dependabot-autosetup` folder in your project.
2. Double-click `dependabot-autosetup.bat`.

> ⚠️ **Windows will likely block it on first run** (Smart App Control / SmartScreen) since it's a freshly downloaded script -- this is Windows being cautious about downloaded files in general, not a virus warning.

<details>
<summary><strong>How to unblock it</strong></summary>

- Right-click `dependabot-autosetup.bat` → **Properties**
- Check the **Unblock** checkbox at the bottom of the General tab (only appears if Windows has flagged it)

![Unblock checkbox in the file Properties dialog](https://raw.githubusercontent.com/dlr-developer/dependabot-autosetup/main/scripts/dependabot-autosetup/unblock-screenshot-windows.png)

- Click **Apply**, then **OK**
- Do the same for `dependabot-autosetup.sh`
- Double-click `dependabot-autosetup.bat` again

If you don't see an Unblock checkbox and it's still refused, run this in PowerShell instead (adjust the path):

```powershell
Unblock-File -Path "C:\path\to\scripts\dependabot-autosetup\dependabot-autosetup.bat"
Unblock-File -Path "C:\path\to\scripts\dependabot-autosetup\dependabot-autosetup.sh"
```

</details>

Requires [Git for Windows](https://git-scm.com/download/win) (the `.bat` launches your script through Git's bundled Bash).

---

## ✨ What it does

| | |
|---|---|
| 🔍 **Detects** | Scans for manifest files across ~30 ecosystems (npm, cargo, pip, gradle, docker, and more) |
| 📝 **Configures** | Writes `.github/dependabot.yml` with a weekly schedule per detected ecosystem |
| 🔀 **Auto-merges** | Optional GitHub Action for low-risk and/or high-risk updates -- your choice, explained at setup |
| ✅ **Verifies** | Checks the target GitHub repo actually exists before pushing, offers to create it if not |
| 🔒 **Manages** | Toggle Dependabot security alert emails and repo visibility (public/private) |
| 🔁 **Re-runnable** | Check status and change settings any time -- won't duplicate work already done |
| 🧬 **Self-updating** | Looks up new Dependabot ecosystems automatically as GitHub adds support for them |

---

## 🧭 Step-by-step walkthrough

**First run on a repo:**

1. If you installed via curl, it already launched automatically -- otherwise run `./scripts/dependabot-autosetup/dependabot-autosetup.sh` (or double-click `dependabot-autosetup.bat`) from inside your project.
2. If GitHub CLI (`gh`) isn't installed or signed in, it'll offer to install it and walk you through sign-in -- your browser will open for a one-time code.
3. It confirms which GitHub repo it's connected to (or asks you to enter one, and offers to create it -- public or private, your choice -- if it doesn't exist yet).
4. It scans your project and lists the ecosystem(s) it found (npm, cargo, pip, etc.) and writes `.github/dependabot.yml`.
5. It explains **low-risk** (patch/minor) and **high-risk** (major) auto-merge separately, with a recommendation for each, and asks whether to turn them on.
6. It shows current Dependabot security alert status for the repo and lets you turn it on/off.
7. It asks to push -- creates a branch, commits, and opens/merges a PR for you (recommended, since it's just config files).
8. You land on a status menu: re-run setup, toggle auto-merge risk levels, toggle alerts, toggle repo visibility, or exit.

**Every run after that:** it shows you the current status first, then the same menu -- nothing gets duplicated, and you can change any setting at any time by re-running the script.

---

- `bash` (Git Bash on Windows, built-in on macOS/Linux)
- [GitHub CLI](https://cli.github.com) (`gh`) -- optional, but needed for repo verification, repo creation, and security alert toggling. The script offers to help you install and sign in if it's missing.

---

## 🔗 Related

- [github.com/dependabot](https://github.com/dependabot) -- the official Dependabot project this tool automates setup for
