#!/bin/bash
set -e
#
# install-dependabot-autosetup.sh -- installs all dependabot-autosetup files into
# ./scripts/dependabot-autosetup (nested, so it never collides with other
# scripts already in your project's scripts/ folder).
# Part of dependabot-autosetup: https://github.com/dlr-developer/dependabot-autosetup
# Not affiliated with GitHub or Dependabot.

BASE_URL="https://raw.githubusercontent.com/dlr-developer/dependabot-autosetup/main"
SCRIPT_URL="$BASE_URL/scripts/dependabot-autosetup/dependabot-autosetup.sh"
INSTALLER_URL="$BASE_URL/scripts/dependabot-autosetup/install-dependabot-autosetup.sh"
README_URL="$BASE_URL/README.md"
SCREENSHOT_URL="$BASE_URL/scripts/dependabot-autosetup/unblock-screenshot-windows.png"
TARGET_DIR="scripts/dependabot-autosetup"

echo "Installing dependabot-autosetup into ./$TARGET_DIR ..."
mkdir -p "$TARGET_DIR"

if ! curl -fsSL "$SCRIPT_URL" -o "$TARGET_DIR/dependabot-autosetup.sh"; then
  echo "Could not download dependabot-autosetup.sh. Check your connection or the URL in this installer."
  exit 1
fi
chmod +x "$TARGET_DIR/dependabot-autosetup.sh"

# Keep a local copy of this installer too, so you can re-run it later to update
# without needing to go back to the README for the command.
curl -fsSL "$INSTALLER_URL" -o "$TARGET_DIR/install-dependabot-autosetup.sh" 2>/dev/null || echo "(Could not fetch install-dependabot-autosetup.sh -- not critical, continuing.)"
chmod +x "$TARGET_DIR/install-dependabot-autosetup.sh" 2>/dev/null || true

# Drop a copy of the README right next to the tool, so anyone who ends up with
# just this folder (no root README nearby) still has the instructions.
curl -fsSL "$README_URL" -o "$TARGET_DIR/README.md" 2>/dev/null || echo "(Could not fetch README.md -- not critical, continuing.)"

# Same for the unblock screenshot the README references -- keeps the local
# README fully readable even without internet access.
curl -fsSL "$SCREENSHOT_URL" -o "$TARGET_DIR/unblock-screenshot-windows.png" 2>/dev/null || echo "(Could not fetch unblock-screenshot-windows.png -- not critical, continuing.)"

# Generate the .bat locally -- this file never touches the internet directly,
# so Windows won't tag it with Mark-of-the-Web, which is what triggers
# Smart App Control / SmartScreen blocking a downloaded .bat.
cat > "$TARGET_DIR/dependabot-autosetup.bat" << 'BAT_EOF'
@echo off
setlocal
rem dependabot-autosetup.bat -- launches dependabot-autosetup.sh via Git Bash.
rem Part of dependabot-autosetup: https://github.com/dlr-developer/dependabot-autosetup
rem Not affiliated with GitHub or Dependabot.

set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo Git Bash not found. Install Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

"%BASH_EXE%" -c "cd \"$(dirname \"$0\")\" && ./dependabot-autosetup.sh; echo; read -p 'Press enter to close...'" "%~dp0dependabot-autosetup.sh"

endlocal
BAT_EOF

echo ""
echo "Done. Installed to ./$TARGET_DIR/:"
echo "  dependabot-autosetup.sh"
echo "  dependabot-autosetup.bat"
echo "  install-dependabot-autosetup.sh"
echo "  README.md"
echo "  unblock-screenshot-windows.png"
echo ""

# Auto-launch the tool. When this installer itself was run via `curl ... | bash`,
# stdin is the pipe carrying this script's own text, not your keyboard -- so we
# explicitly redirect the launched script's stdin to the real terminal, or its
# interactive prompts would silently break. If no terminal is actually available
# (e.g. a non-interactive/CI context), skip auto-launch and just show the command.
if (exec 3< /dev/tty) 2>/dev/null; then
  exec 3<&-
  echo "Launching dependabot-autosetup.sh..."
  echo ""
  "$TARGET_DIR/dependabot-autosetup.sh" < /dev/tty
else
  echo "Run it with: ./$TARGET_DIR/dependabot-autosetup.sh"
  echo "Or on Windows, double-click $TARGET_DIR/dependabot-autosetup.bat"
fi