@echo off
setlocal
rem dependabot-manager.bat -- launches dependabot-manager.sh via Git Bash.
rem Part of dependabot-autosetup: https://github.com/dlr-developer/dependabot-autosetup
rem Not affiliated with GitHub or Dependabot.

set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"

if not exist "%BASH_EXE%" (
    echo Git Bash not found. Install Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

"%BASH_EXE%" -c "cd \"$(dirname \"$0\")\" && ./dependabot-manager.sh" "%~dp0dependabot-manager.sh"

endlocal
