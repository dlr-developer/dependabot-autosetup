#!/bin/bash
#
# dependabot-autosetup.sh -- automates setting up GitHub Dependabot on a repo.
# Part of dependabot-autosetup: https://github.com/dlr-developer/dependabot-autosetup
# Not affiliated with GitHub or Dependabot.

# ============================================================================
# COLOR KEY -- what each color means throughout this script:
#   C_HEADER  bold cyan    section headers, and the number in numbered menus (e.g. "1)")
#   C_LABEL   bold white   field labels ("Currently:") and important explanatory sentences
#   C_ON      bold green   "on" / success / good news / recommended-and-chosen
#   C_OFF     gray         "off" / neutral / de-emphasized / informational side notes
#   C_WARN    bold yellow  caution -- needs attention but isn't a failure
#   C_DANGER  bold red     failures, errors, and high-risk states
#   C_PROMPT  bold blue    every read -p input prompt
# ============================================================================

# Colors (fall back to no color if the terminal doesn't support it)
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_HEADER='\033[1;36m'   # bold cyan -- section headers
  C_LABEL='\033[1;37m'    # bold white -- field labels
  C_ON='\033[1;32m'       # bold green -- "on" / good / recommended
  C_OFF='\033[0;90m'      # gray -- "off" / neutral
  C_WARN='\033[1;33m'     # bold yellow -- caution
  C_DANGER='\033[1;31m'   # bold red -- high risk
  C_PROMPT='\033[1;34m'   # bold blue -- input prompts
else
  C_RESET=''; C_BOLD=''; C_HEADER=''; C_LABEL=''; C_ON=''; C_OFF=''; C_WARN=''; C_DANGER=''; C_PROMPT=''
fi

# If this script lives anywhere under a folder named "scripts" (directly, or nested
# further inside like scripts/dependabot-autosetup/), operate from that scripts
# folder's parent instead (the project root) -- .github/ must sit at the project
# root, not inside /scripts.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SEARCH_DIR="$SELF_DIR"
while [ "$SEARCH_DIR" != "/" ]; do
  if [ "$(basename "$SEARCH_DIR")" == "scripts" ]; then
    cd "$(dirname "$SEARCH_DIR")"
    echo -e "${C_OFF}Running from project root: $(pwd)${C_RESET}"
    break
  fi
  SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

# Make sure this folder is actually a git repo before anything else touches git.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo ""
  echo -e "${C_WARN}This folder isn't a git repository yet.${C_RESET}"
  read -p "$(echo -e "${C_PROMPT}Run 'git init' here now? [Y/n]: ${C_RESET}")" INIT_ANS
  INIT_ANS=${INIT_ANS:-Y}
  case "$INIT_ANS" in
    y|Y)
      git init -q -b main 2>/dev/null || git init -q
      echo -e "${C_ON}Initialized a git repo here.${C_RESET}"
      ;;
    *)
      echo -e "${C_DANGER}Can't continue without a git repo in this folder.${C_RESET}"
      exit 1
      ;;
  esac
fi

KNOWN_ECOSYSTEMS="npm gradle pip bundler gomod docker docker-compose composer cargo maven mix pub elm swift nuget terraform devcontainers gitsubmodule github-actions bazel bun conda deno dotnet-sdk helm julia nix opentofu pre-commit rust-toolchain sbt uv vcpkg"
SCRIPT_PATH="${SELF_DIR}/$(basename "$0")"
NEWLY_ADDED_ECOS=()

CUSTOM_REPO=""
for arg in "$@"; do
  case $arg in
    --repo=*) CUSTOM_REPO="${arg#--repo=}" ;;
  esac
done

# ================= Self-updating ecosystem detection =================
add_ecosystem_to_script() {
  local eco="$1" pattern="$2"
  local newline="[ -f \"$pattern\" ] && ECOSYSTEMS+=(\"$eco\")"
  awk -v line="$newline" '/# ECOSYSTEM_DETECTION_END/{print line} {print}' "$SCRIPT_PATH" > "${SCRIPT_PATH}.tmp"
  mv "${SCRIPT_PATH}.tmp" "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  sed -i "s/^KNOWN_ECOSYSTEMS=\"\(.*\)\"/KNOWN_ECOSYSTEMS=\"\1 $eco\"/" "$SCRIPT_PATH"
  NEWLY_ADDED_ECOS+=("$eco:$pattern")
}

try_auto_lookup() {
  local eco="$1" folder_guess="${1//-/_}"
  for guess in "$eco" "$folder_guess"; do
    local url="https://raw.githubusercontent.com/dependabot/dependabot-core/main/${guess}/lib/dependabot/${guess}/file_fetcher.rb"
    local content
    content=$(curl -fsSL --max-time 4 "$url" 2>/dev/null) || continue
    local manifest
    manifest=$(echo "$content" | grep -A 3 'required_files_in?' | grep -oP '"\K[^"]+' | head -1)
    [ -n "$manifest" ] && { echo "$manifest"; return 0; }
  done
  return 1
}

check_for_new_ecosystems() {
  local DOCS_URL="https://raw.githubusercontent.com/github/docs/main/data/reusables/dependabot/supported-package-managers.md"
  local PAGE
  PAGE=$(curl -fsSL --max-time 3 "$DOCS_URL" 2>/dev/null) || return 0
  local LIVE_ECOSYSTEMS
  LIVE_ECOSYSTEMS=$(echo "$PAGE" | grep -oP '\|\s*`\K[a-z0-9.-]+(?=`\s*\|)' | sort -u)
  [ -z "$LIVE_ECOSYSTEMS" ] && return 0
  for eco in $LIVE_ECOSYSTEMS; do
    echo " $KNOWN_ECOSYSTEMS " | grep -q " $eco " && continue
    echo -e "${C_WARN}New Dependabot ecosystem found: '$eco'.${C_RESET} Looking up its manifest file automatically..."
    local manifest
    if manifest=$(try_auto_lookup "$eco"); then
      echo -e "${C_ON}Found it:${C_RESET} '$eco' is identified by $manifest. Adding detection automatically."
      add_ecosystem_to_script "$eco" "$manifest"
    else
      echo -e "${C_WARN}Couldn't auto-resolve '$eco'${C_RESET} -- dependabot-core's folder name for it doesn't match the usual pattern."
      read -p "$(echo -e "${C_PROMPT}What filename identifies a '$eco' project? (or press enter to skip): ${C_RESET}")" MANUAL_PATTERN
      if [ -n "$MANUAL_PATTERN" ]; then
        add_ecosystem_to_script "$eco" "$MANUAL_PATTERN"
        echo -e "${C_ON}Added.${C_RESET} This script now detects '$eco' automatically going forward."
      else
        echo -e "${C_OFF}Skipped. Will ask again next time.${C_RESET}"
      fi
    fi
  done
}
check_for_new_ecosystems

detect_ecosystems() {
  ECOSYSTEMS=()
  [ -f package.json ] && ECOSYSTEMS+=("npm")
  { [ -f build.gradle ] || [ -f build.gradle.kts ]; } && ECOSYSTEMS+=("gradle")
  { [ -f requirements.txt ] || [ -f pyproject.toml ]; } && ECOSYSTEMS+=("pip")
  [ -f Gemfile ] && ECOSYSTEMS+=("bundler")
  [ -f go.mod ] && ECOSYSTEMS+=("gomod")
  [ -f Dockerfile ] && ECOSYSTEMS+=("docker")
  { [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; } && ECOSYSTEMS+=("docker-compose")
  [ -f composer.json ] && ECOSYSTEMS+=("composer")
  [ -f Cargo.toml ] && ECOSYSTEMS+=("cargo")
  [ -f pom.xml ] && ECOSYSTEMS+=("maven")
  [ -f mix.exs ] && ECOSYSTEMS+=("mix")
  [ -f pubspec.yaml ] && ECOSYSTEMS+=("pub")
  [ -f elm.json ] && ECOSYSTEMS+=("elm")
  [ -f Package.swift ] && ECOSYSTEMS+=("swift")
  { compgen -G "*.csproj" >/dev/null 2>&1 || compgen -G "*.sln" >/dev/null 2>&1 || [ -f packages.config ]; } && ECOSYSTEMS+=("nuget")
  compgen -G "*.tf" >/dev/null 2>&1 && ECOSYSTEMS+=("terraform")
  [ -d .devcontainer ] && ECOSYSTEMS+=("devcontainers")
  [ -f .gitmodules ] && ECOSYSTEMS+=("gitsubmodule")
  ECOSYSTEMS+=("github-actions")
  { [ -f WORKSPACE ] || [ -f WORKSPACE.bazel ] || [ -f MODULE.bazel ]; } && ECOSYSTEMS+=("bazel")
  [ -f bun.lock ] && ECOSYSTEMS+=("bun")
  { [ -f environment.yml ] || [ -f environment.yaml ]; } && ECOSYSTEMS+=("conda")
  { [ -f deno.json ] || [ -f deno.jsonc ]; } && ECOSYSTEMS+=("deno")
  [ -f global.json ] && ECOSYSTEMS+=("dotnet-sdk")
  [ -f Chart.yaml ] && ECOSYSTEMS+=("helm")
  { [ -f Project.toml ] || [ -f Manifest.toml ]; } && ECOSYSTEMS+=("julia")
  [ -f flake.lock ] && ECOSYSTEMS+=("nix")
  { compgen -G "*.tofu" >/dev/null 2>&1 || [ -f terragrunt.hcl ]; } && ECOSYSTEMS+=("opentofu")
  [ -f .pre-commit-config.yaml ] && ECOSYSTEMS+=("pre-commit")
  { [ -f rust-toolchain.toml ] || [ -f rust-toolchain ]; } && ECOSYSTEMS+=("rust-toolchain")
  [ -f build.sbt ] && ECOSYSTEMS+=("sbt")
  [ -f uv.lock ] && ECOSYSTEMS+=("uv")
  [ -f vcpkg.json ] && ECOSYSTEMS+=("vcpkg")
  # ECOSYSTEM_DETECTION_END
  for entry in "${NEWLY_ADDED_ECOS[@]}"; do
    eco="${entry%%:*}"; pattern="${entry#*:}"
    [ -f "$pattern" ] && ECOSYSTEMS+=("$eco")
  done
  ECOSYSTEMS=($(printf "%s\n" "${ECOSYSTEMS[@]}" | sort -u))
}

# ================= GitHub connection (account, repo target, verification) =================
HAVE_GH=false
REPO_TARGET=""
GITHUB_SKIPPED=false

connect_github() {
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      HAVE_GH=true
      GH_ACCOUNT=$(gh api user --jq .login 2>/dev/null)
      echo -e "${C_ON}Signed in to GitHub CLI as: ${GH_ACCOUNT:-unknown}${C_RESET}"
    else
      echo ""
      echo -e "${C_WARN}gh CLI is installed but not signed in.${C_RESET} Repo verification and security alert toggling need this."
      read -p "$(echo -e "${C_PROMPT}Sign in now? [y/n]: ${C_RESET}")" GH_LOGIN_ANS
      case "$GH_LOGIN_ANS" in
        y|Y) gh auth login && HAVE_GH=true ;;
        *) echo -e "${C_OFF}Skipping repo verification and security alerts.${C_RESET}" ;;
      esac
    fi
  else
    echo ""
    echo -e "${C_WARN}GitHub CLI (gh) isn't installed.${C_RESET} Without it, this script can't check whether a"
    echo "GitHub repo actually exists before pushing to it -- pushes can fail with a"
    echo "confusing git error if the repo isn't there yet."
    echo ""
    echo -e "  ${C_HEADER}1)${C_RESET} Install it now ${C_OFF}(winget, Windows only)${C_RESET}"
    echo -e "  ${C_HEADER}2)${C_RESET} I'll install it myself -- ${C_LABEL}https://cli.github.com${C_RESET}"
    echo -e "  ${C_HEADER}3)${C_RESET} Skip -- continue without repo verification or alert toggling"
    read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" GH_INSTALL_CHOICE
    case $GH_INSTALL_CHOICE in
      1)
        if command -v winget >/dev/null 2>&1; then
          winget install --id GitHub.cli -e --source winget
          echo ""
          for CANDIDATE_PATH in "/c/Program Files/GitHub CLI" "/c/Program Files (x86)/GitHub CLI"; do
            [ -d "$CANDIDATE_PATH" ] && export PATH="$PATH:$CANDIDATE_PATH"
          done
          if command -v gh >/dev/null 2>&1; then
            echo -e "${C_ON}Installed.${C_RESET} Signing in..."
            gh auth login && HAVE_GH=true
            if [ "$HAVE_GH" == "true" ]; then
              GH_ACCOUNT=$(gh api user --jq .login 2>/dev/null)
              echo -e "${C_ON}Signed in to GitHub CLI as: ${GH_ACCOUNT:-unknown}${C_RESET}"
            fi
          else
            echo -e "${C_WARN}Installed, but this terminal can't see it yet.${C_RESET} Close and reopen your terminal, then re-run this script."
            exit 0
          fi
        else
          echo -e "${C_WARN}winget isn't available here.${C_RESET} Install manually: ${C_LABEL}https://cli.github.com${C_RESET}"
        fi
        ;;
      2)
        echo -e "Get it here: ${C_LABEL}https://cli.github.com${C_RESET} -- then re-run this script."
        ;;
      *)
        echo -e "${C_OFF}Skipping repo verification and security alerts.${C_RESET}"
        ;;
    esac
  fi

  if [ -n "$CUSTOM_REPO" ]; then
    REPO_TARGET="$CUSTOM_REPO"
  elif git remote get-url origin >/dev/null 2>&1; then
    REPO_TARGET=$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')
    echo -e "${C_ON}Already connected to: $REPO_TARGET${C_RESET} (from existing git origin)"
  else
    echo ""
    echo -e "${C_WARN}No GitHub repo linked yet${C_RESET} (local folder: $(basename "$PWD"))."
    SUGGESTED_REPO="${GH_ACCOUNT:-$(gh api user --jq .login 2>/dev/null)}/$(basename "$PWD")"
    REPO_TARGET=""
    while [ -z "$REPO_TARGET" ] && [ "$GITHUB_SKIPPED" != "true" ]; do
      echo -e "  ${C_HEADER}1)${C_RESET} Use $SUGGESTED_REPO"
      echo -e "  ${C_HEADER}2)${C_RESET} Enter a different GitHub repo"
      echo -e "  ${C_HEADER}3)${C_RESET} Skip GitHub features"
      read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" REPO_CHOICE
      case $REPO_CHOICE in
        1) REPO_TARGET="$SUGGESTED_REPO" ;;
        2) read -p "$(echo -e "${C_PROMPT}Enter the GitHub repo as owner/name: ${C_RESET}")" REPO_TARGET ;;
        3) GITHUB_SKIPPED=true ;;
        *) echo -e "${C_DANGER}Invalid choice.${C_RESET}" ;;
      esac
    done
  fi

  if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
    while ! gh repo view "$REPO_TARGET" >/dev/null 2>&1; do
      SUGGESTED_REPO="${GH_ACCOUNT:-$(gh api user --jq .login 2>/dev/null)}/$(basename "$PWD")"
      echo ""
      echo -e "${C_DANGER}Repo '$REPO_TARGET' wasn't found on GitHub${C_RESET} (or you don't have access to it)."
      echo -e "This folder is named ${C_LABEL}$(basename "$PWD")${C_RESET} -- did you mean ${C_LABEL}$SUGGESTED_REPO${C_RESET}?"
      echo -e "  ${C_HEADER}1)${C_RESET} Create it now on GitHub"
      echo -e "  ${C_HEADER}2)${C_RESET} Enter a different repo"
      echo -e "  ${C_HEADER}3)${C_RESET} Skip -- work locally only"
      read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" REPO_FIX_CHOICE
      case $REPO_FIX_CHOICE in
        1)
          REPO_TARGET="$SUGGESTED_REPO"
          echo ""
          echo -e "${C_LABEL}Public or private?${C_RESET}"
          echo -e "  ${C_HEADER}1)${C_RESET} Private"
          echo -e "  ${C_HEADER}2)${C_RESET} Public"
          read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" VIS_ANS
          case "$VIS_ANS" in
            2) gh repo create "$REPO_TARGET" --public ;;
            *) gh repo create "$REPO_TARGET" --private ;;
          esac
          # Lock in the correct default branch immediately. A brand-new empty GitHub
          # repo has no real default branch until something with a commit is pushed --
          # whatever branch gets pushed FIRST becomes the default. If we don't push
          # main here right away, the later add-dependabot push would claim that
          # spot instead, breaking the PR step (head branch == base branch).
          CURRENT_LOCAL_BRANCH=$(git branch --show-current)
          if [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
            git commit --allow-empty -m "Initial commit" -q
          fi
          git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/${REPO_TARGET}.git"
          if git push -u origin "$CURRENT_LOCAL_BRANCH":main -q; then
            echo -e "${C_ON}Established 'main' as the default branch on GitHub.${C_RESET}"
          else
            echo -e "${C_DANGER}Couldn't push an initial commit to main.${C_RESET} The next push may end up setting the wrong default branch."
          fi
          break
          ;;
        2) read -p "$(echo -e "${C_PROMPT}Enter the correct repo as owner/name (default: $SUGGESTED_REPO): ${C_RESET}")" REPO_TARGET
           REPO_TARGET=${REPO_TARGET:-$SUGGESTED_REPO}
           ;;
        3) REPO_TARGET=""; break ;;
        *) echo -e "${C_DANGER}Invalid choice.${C_RESET}" ;;
      esac
    done
  fi

  if [ -n "$REPO_TARGET" ] && ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/${REPO_TARGET}.git"
  fi
}

# ================= Status check =================
LOCAL_CONFIG=false; LOCAL_WORKFLOW=false; GH_CONFIG=false; GH_WORKFLOW=false
RISK_MODE="none"; ALERTS_STATUS="unknown"; RUN_INTERVAL="weekly"
WORKFLOW_FILE=".github/workflows/dependabot-auto-merge.yml"

refresh_status() {
  LOCAL_CONFIG=false; LOCAL_WORKFLOW=false; GH_CONFIG=false; GH_WORKFLOW=false
  [ -f .github/dependabot.yml ] && LOCAL_CONFIG=true
  [ -f "$WORKFLOW_FILE" ] && LOCAL_WORKFLOW=true

  if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
    gh api "repos/$REPO_TARGET/contents/.github/dependabot.yml" >/dev/null 2>&1 && GH_CONFIG=true
    gh api "repos/$REPO_TARGET/contents/$WORKFLOW_FILE" >/dev/null 2>&1 && GH_WORKFLOW=true
  fi

  # Attempt to extract schedule interval from local dependabot.yml (default to weekly)
  RUN_INTERVAL="weekly"
  if [ "$LOCAL_CONFIG" == "true" ]; then
    local EXTRACTED
    EXTRACTED=$(grep -m 1 "interval:" .github/dependabot.yml | awk -F'"' '{print $2}' | tr -d ' ')
    [ -z "$EXTRACTED" ] && EXTRACTED=$(grep -m 1 "interval:" .github/dependabot.yml | awk '{print $2}' | tr -d '"'\'' ')
    [ -n "$EXTRACTED" ] && RUN_INTERVAL="$EXTRACTED"
  fi

  RISK_MODE="none"
  if [ "$LOCAL_WORKFLOW" = true ]; then
    if grep -q "semver-patch" "$WORKFLOW_FILE" 2>/dev/null; then
      RISK_MODE="low"
      grep -q "semver-major" "$WORKFLOW_FILE" 2>/dev/null && RISK_MODE="all"
    elif grep -q "gh pr merge" "$WORKFLOW_FILE" 2>/dev/null; then
      RISK_MODE="all"
    fi
  fi

  ALERTS_STATUS="unknown"
  if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
    local HTTP_CODE
    HTTP_CODE=$(gh api -i "repos/$REPO_TARGET/vulnerability-alerts" 2>/dev/null | head -1 | awk '{print $2}')
    [ "$HTTP_CODE" == "204" ] && ALERTS_STATUS="on"
    [ "$HTTP_CODE" == "404" ] && ALERTS_STATUS="off"
  fi

  REPO_VISIBILITY="unknown"
  if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
    local VIS_RAW
    VIS_RAW=$(gh repo view "$REPO_TARGET" --json isPrivate --jq .isPrivate 2>/dev/null)
    [ "$VIS_RAW" == "true" ] && REPO_VISIBILITY="private"
    [ "$VIS_RAW" == "false" ] && REPO_VISIBILITY="public"
  fi
}

show_status() {
  echo ""
  echo -e "${C_HEADER}=== ${REPO_TARGET:-$(basename "$PWD")} ===${C_RESET}"

  local_cfg_disp=$([ "$LOCAL_CONFIG" == "true" ] && echo -e "${C_ON}Yes${C_RESET}" || echo -e "${C_OFF}No${C_RESET}")
  local_wf_disp=$([ "$LOCAL_WORKFLOW" == "true" ] && echo -e "${C_ON}Yes${C_RESET}" || echo -e "${C_OFF}No${C_RESET}")
  gh_cfg_disp=$([ "$GH_CONFIG" == "true" ] && echo -e "${C_ON}Yes${C_RESET}" || echo -e "${C_OFF}No${C_RESET}")
  gh_wf_disp=$([ "$GH_WORKFLOW" == "true" ] && echo -e "${C_ON}Yes${C_RESET}" || echo -e "${C_OFF}No${C_RESET}")

  echo -e "${C_LABEL}Dependabot config file written locally:${C_RESET}    $local_cfg_disp"
  echo -e "${C_LABEL}Auto-merge workflow written locally:${C_RESET}      $local_wf_disp"
  echo -e "${C_LABEL}Config file pushed to GitHub:${C_RESET}             $gh_cfg_disp"
  echo -e "${C_LABEL}Auto-merge workflow pushed to GitHub:${C_RESET}     $gh_wf_disp"
  if [ "$RISK_MODE" == "low" ] || [ "$RISK_MODE" == "all" ]; then LOW_DISP="${C_ON}On${C_RESET}"; else LOW_DISP="${C_OFF}Off${C_RESET}"; fi
  if [ "$RISK_MODE" == "all" ]; then HIGH_DISP="${C_DANGER}On${C_RESET}"; else HIGH_DISP="${C_OFF}Off${C_RESET}"; fi
  if [ "$ALERTS_STATUS" == "on" ]; then ALERT_DISP="${C_ON}On${C_RESET}"; elif [ "$ALERTS_STATUS" == "off" ]; then ALERT_DISP="${C_WARN}Off${C_RESET}"; else ALERT_DISP="${C_OFF}Unknown (GitHub not connected)${C_RESET}"; fi
  echo -e "${C_LABEL}Auto-merge low-risk (patch/minor):${C_RESET}        $LOW_DISP"
  echo -e "${C_LABEL}Auto-merge high-risk (major):${C_RESET}             $HIGH_DISP"
  echo -e "${C_LABEL}Security alert emails:${C_RESET}                    $ALERT_DISP"
  if [ "$REPO_VISIBILITY" == "public" ]; then VIS_DISP="${C_WARN}Public${C_RESET}"; elif [ "$REPO_VISIBILITY" == "private" ]; then VIS_DISP="${C_ON}Private${C_RESET}"; else VIS_DISP="${C_OFF}Unknown (GitHub not connected)${C_RESET}"; fi
  echo -e "${C_LABEL}Repo visibility:${C_RESET}                          $VIS_DISP"
  echo -e "${C_LABEL}Check updates schedule interval:${C_RESET}          ${C_ON}${RUN_INTERVAL}${C_RESET}"
  echo ""
}

# ================= Workflow writer =================
write_workflow() {
  local MODE="$1"
  mkdir -p .github/workflows
  if [ "$MODE" == "none" ]; then
    rm -f "$WORKFLOW_FILE"
    echo -e "${C_OFF}Auto-merge disabled.${C_RESET}"
    return
  fi
  {
    echo "name: Dependabot auto-merge"
    echo "on: pull_request"
    echo "permissions:"
    echo "  contents: write"
    echo "  pull-requests: write"
    echo "jobs:"
    echo "  auto-merge:"
    echo "    if: github.actor == 'dependabot[bot]'"
    echo "    runs-on: ubuntu-latest"
    echo "    steps:"
    echo "      - uses: dependabot/fetch-metadata@v2"
    echo "        id: metadata"
    echo "        with:"
    echo "          github-token: \"\${{ secrets.GITHUB_TOKEN }}\""
    if [ "$MODE" == "low" ]; then
      echo "      - if: steps.metadata.outputs.update-type == 'version-update:semver-patch' || steps.metadata.outputs.update-type == 'version-update:semver-minor'"
      echo "        run: gh pr merge --auto --merge \"\$PR_URL\""
    else
      echo "      - run: gh pr merge --auto --merge \"\$PR_URL\"  # includes semver-major"
    fi
    echo "        env:"
    echo "          PR_URL: \${{ github.event.pull_request.html_url }}"
    echo "          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}"
  } > "$WORKFLOW_FILE"
  echo -e "${C_ON}Auto-merge set to: $MODE${C_RESET}"
}

# ================= Setup flow =================
run_setup() {
  detect_ecosystems
  if [ ${#ECOSYSTEMS[@]} -eq 0 ]; then
    echo -e "${C_DANGER}No known ecosystem detected.${C_RESET} Nothing to set up."
    return
  fi

  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
  echo ""
  echo -e "${C_LABEL}Define check updates schedule interval${C_RESET}"
  echo "Available intervals: daily, weekly, monthly"
  echo -e "Recommended: weekly."
  echo -e "${C_LABEL}Currently:${C_RESET} ${RUN_INTERVAL}"
  read -p "$(echo -e "${C_PROMPT}Enter check interval [daily/weekly/monthly] (enter to keep): ${C_RESET}")" USER_INTERVAL
  USER_INTERVAL=${USER_INTERVAL:-$RUN_INTERVAL}
  # Lowercase and sanitize
  USER_INTERVAL=$(echo "$USER_INTERVAL" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  if [ "$USER_INTERVAL" != "daily" ] && [ "$USER_INTERVAL" != "weekly" ] && [ "$USER_INTERVAL" != "monthly" ]; then
    echo -e "${C_WARN}Invalid choice. Defaulting to weekly.${C_RESET}"
    USER_INTERVAL="weekly"
  fi
  RUN_INTERVAL="$USER_INTERVAL"

  mkdir -p .github/workflows
  {
    echo "version: 2"
    echo "updates:"
    for eco in "${ECOSYSTEMS[@]}"; do
      echo "  - package-ecosystem: \"$eco\""
      echo "    directory: \"/\""
      echo "    schedule:"
      echo "      interval: \"$RUN_INTERVAL\""
    done
  } > .github/dependabot.yml
  echo -e "${C_ON}Detected: ${ECOSYSTEMS[*]}${C_RESET}"
  echo -e "${C_ON}Written .github/dependabot.yml${C_RESET}"

  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
  echo ""
  CURRENT_LOW_ANS=$([ "$RISK_MODE" == "low" ] || [ "$RISK_MODE" == "all" ] && echo "y" || echo "n")
  CURRENT_HIGH_ANS=$([ "$RISK_MODE" == "all" ] && echo "y" || echo "n")
  echo -e "${C_HEADER}Low-risk${C_RESET} = patch/minor version bumps (e.g. 1.2.3 -> 1.2.4 or 1.3.0). These are"
  echo "meant to be backward-compatible, so they rarely break anything."
  echo -e "${C_ON}Recommended: on.${C_RESET}"
  if [ "$CURRENT_LOW_ANS" == "y" ]; then echo -e "${C_LABEL}Currently:${C_RESET} ${C_ON}On${C_RESET}"; else echo -e "${C_LABEL}Currently:${C_RESET} ${C_OFF}Off${C_RESET}"; fi
  read -p "$(echo -e "${C_PROMPT}Auto-merge low-risk (patch/minor) updates? [y/n] (enter to keep): ${C_RESET}")" LOW_ANS
  LOW_ANS=${LOW_ANS:-$CURRENT_LOW_ANS}
  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
  echo ""
  echo -e "${C_HEADER}High-risk${C_RESET} = major version bumps (e.g. 1.x.x -> 2.0.0). These CAN include breaking"
  echo "API changes, so auto-merging them unattended risks shipping something that breaks"
  echo "your build without you reviewing it first."
  echo -e "${C_DANGER}Recommended: off -- review these manually.${C_RESET}"
  if [ "$CURRENT_HIGH_ANS" == "y" ]; then echo -e "${C_LABEL}Currently:${C_RESET} ${C_DANGER}On${C_RESET}"; else echo -e "${C_LABEL}Currently:${C_RESET} ${C_OFF}Off${C_RESET}"; fi
  read -p "$(echo -e "${C_PROMPT}Auto-merge high-risk (major) updates? [y/n] (enter to keep): ${C_RESET}")" HIGH_ANS
  HIGH_ANS=${HIGH_ANS:-$CURRENT_HIGH_ANS}
  MODE="none"
  case "$LOW_ANS" in y|Y) case "$HIGH_ANS" in y|Y) MODE="all" ;; *) MODE="low" ;; esac ;; esac
  write_workflow "$MODE"

  if [ -z "$REPO_TARGET" ] && [ "$GITHUB_SKIPPED" != "true" ]; then
    connect_github
  fi

  if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
    echo ""
    echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
    echo ""
    if [ "$ALERTS_STATUS" == "on" ]; then ALERT_STATUS_DISP="${C_ON}On${C_RESET}"; else ALERT_STATUS_DISP="${C_OFF}Off${C_RESET}"; fi
    echo -e "${C_LABEL}Security alert emails for $REPO_TARGET${C_RESET}"
    echo -e "${C_LABEL}Currently:${C_RESET} $ALERT_STATUS_DISP"
    CURRENT_ALERTS_ANS=$([ "$ALERTS_STATUS" == "on" ] && echo "y" || echo "n")
    read -p "$(echo -e "${C_PROMPT}Turn them on? [y/n] (enter to keep): ${C_RESET}")" ALERTS_ANS
    ALERTS_ANS=${ALERTS_ANS:-$CURRENT_ALERTS_ANS}
    case "$ALERTS_ANS" in
      y|Y) gh api -X PUT "repos/$REPO_TARGET/vulnerability-alerts" >/dev/null 2>&1 && echo -e "${C_ON}Turned ON.${C_RESET}" ;;
      *) gh api -X DELETE "repos/$REPO_TARGET/vulnerability-alerts" >/dev/null 2>&1 && echo -e "${C_OFF}Turned OFF.${C_RESET}" ;;
    esac
  fi

  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
  echo ""
  push_changes
}

push_changes() {
  if [ -n "$REPO_TARGET" ]; then
    read -p "$(echo -e "${C_PROMPT}Push now to branch 'add-dependabot'? [y/n]: ${C_RESET}")" PUSH_ANS
    case "$PUSH_ANS" in
      y|Y)
        DEFAULT_BRANCH=""
        if [ "$HAVE_GH" == "true" ] && [ -n "$REPO_TARGET" ]; then
          DEFAULT_BRANCH=$(gh repo view "$REPO_TARGET" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
        fi
        if [ -z "$DEFAULT_BRANCH" ]; then
          DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
        fi
        if [ -z "$DEFAULT_BRANCH" ]; then
          DEFAULT_BRANCH=$(git branch --list --format='%(refname:short)' | grep -v '^add-dependabot$' | grep -E '^(main|master)$' | head -1)
        fi

        if [ "$DEFAULT_BRANCH" == "add-dependabot" ]; then
          # This repo's default branch is itself named add-dependabot (happens if the
          # very first commit ever pushed here landed on that branch name before any
          # main/master existed). There's nothing to open a PR into -- just push directly.
          echo -e "${C_WARN}This repo's default branch is 'add-dependabot' itself${C_RESET} -- pushing straight to it, no PR needed."
          git add .github
          [ -d scripts/dependabot-autosetup ] && git add scripts/dependabot-autosetup
          if git commit -m "Add Dependabot config and auto-merge workflow"; then
            :
          else
            echo -e "${C_OFF}Nothing new to commit.${C_RESET}"
          fi
          if git push; then
            echo -e "${C_ON}Pushed directly to $DEFAULT_BRANCH.${C_RESET} Config is live."
          else
            echo -e "${C_DANGER}Push failed.${C_RESET} Check the error above."
          fi
          return
        fi

        COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
        CURRENT_BRANCH_NOW=$(git branch --show-current)
        if [ "$COMMIT_COUNT" -le 1 ] && [ "$CURRENT_BRANCH_NOW" == "$DEFAULT_BRANCH" ]; then
          # This is the very first real commit for this repo (at most the empty
          # "Initial commit" made when the repo was created). No point creating a
          # disposable branch and PR for a repo with no history to diverge from --
          # just commit and push straight to the default branch.
          echo -e "${C_WARN}This is the first real commit for this repo${C_RESET} -- pushing straight to $DEFAULT_BRANCH, no PR needed."
          git add .github
          [ -d scripts/dependabot-autosetup ] && git add scripts/dependabot-autosetup
          if git commit -m "Add Dependabot config and auto-merge workflow"; then
            :
          else
            echo -e "${C_OFF}Nothing new to commit.${C_RESET}"
          fi
          if git push -u origin "$DEFAULT_BRANCH"; then
            echo -e "${C_ON}Pushed directly to $DEFAULT_BRANCH.${C_RESET} Config is live."
          else
            echo -e "${C_WARN}Push was rejected${C_RESET} -- the remote already has commits this fresh local repo doesn't know about (likely leftover from an earlier session). Retrying with --force since there's nothing local worth preserving yet."
            if git push -u origin "$DEFAULT_BRANCH" --force; then
              echo -e "${C_ON}Pushed directly to $DEFAULT_BRANCH (forced).${C_RESET} Config is live."
            else
              echo -e "${C_DANGER}Push failed.${C_RESET} Check the error above."
            fi
          fi
          return
        fi

        UNRELATED_CHANGES=$(git status --porcelain | grep -v -E '^\?\? \.github/|^ M \.github/|^A  \.github/|^\?\? scripts/dependabot-autosetup/|^ M scripts/dependabot-autosetup/|^A  scripts/dependabot-autosetup/' || true)
        if [ -n "$UNRELATED_CHANGES" ]; then
          echo ""
          echo -e "${C_WARN}Found uncommitted files that have nothing to do with this tool:${C_RESET}"
          echo -e "${C_OFF}$UNRELATED_CHANGES${C_RESET}"
          echo ""
          echo "The Dependabot files (.github/, scripts/dependabot-autosetup/) always get committed"
          echo "automatically -- no prompt needed for those. This is only about the files listed above."
          echo ""
          local UNCOMMITTED_CHOICE=""
          while true; do
            echo -e "  ${C_HEADER}1)${C_RESET} Commit them to $DEFAULT_BRANCH now ${C_ON}(Recommended -- simplest, safest)${C_RESET}"
            echo -e "  ${C_HEADER}2)${C_RESET} Commit them to a new separate branch ${C_OFF}(keeps $DEFAULT_BRANCH clean, review later)${C_RESET}"
            echo -e "  ${C_HEADER}3)${C_RESET} Skip -- leave them uncommitted and continue ${C_DANGER}(risk: could be lost)${C_RESET}"
            echo -e "  ${C_HEADER}4)${C_RESET} Cancel -- stop here, don't push anything"
            read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" UNCOMMITTED_CHOICE
            case "$UNCOMMITTED_CHOICE" in
              1|2|3|4) break ;;
              *) echo -e "${C_DANGER}Invalid choice. Please enter 1, 2, 3, or 4.${C_RESET}" ;;
            esac
          done

          case "$UNCOMMITTED_CHOICE" in
            1)
              CURRENT_BRANCH_BEFORE=$(git branch --show-current)
              if [ "$CURRENT_BRANCH_BEFORE" != "$DEFAULT_BRANCH" ]; then
                git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null
              fi
              git add -A
              git commit -m "Uncommitted changes before dependabot update"
              git push -u origin "$DEFAULT_BRANCH" 2>/dev/null
              echo -e "${C_ON}Committed and pushed to $DEFAULT_BRANCH.${C_RESET} Continuing..."
              ;;
            2)
              SIDE_BRANCH="wip-$(date +%Y%m%d-%H%M%S)"
              git checkout -b "$SIDE_BRANCH"
              git add -A
              git commit -m "Uncommitted changes before dependabot update"
              git push -u origin "$SIDE_BRANCH" 2>/dev/null
              git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null
              echo -e "${C_ON}Committed and pushed to $SIDE_BRANCH.${C_RESET} Continuing on $DEFAULT_BRANCH..."
              ;;
            3)
              echo -e "${C_WARN}Continuing without committing.${C_RESET}"
              ;;
            4)
              echo -e "${C_OFF}Cancelled. Nothing pushed.${C_RESET}"
              return
              ;;
          esac
        fi

        git stash push -u -m "dependabot-temp"
        STASHED=$?
        git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" "origin/$DEFAULT_BRANCH" 2>/dev/null
        # Sync local $DEFAULT_BRANCH with the remote before branching off it -- otherwise
        # a stale local branch produces a PR based on old content, which can genuinely
        # conflict with whatever's actually on GitHub now.
        git fetch origin "$DEFAULT_BRANCH" 2>/dev/null
        git reset --hard "origin/$DEFAULT_BRANCH" 2>/dev/null
        git branch -D add-dependabot 2>/dev/null
        git checkout -b add-dependabot 2>/dev/null || git checkout add-dependabot
        if [ $STASHED -eq 0 ]; then
          if ! git stash pop; then
            echo -e "${C_DANGER}Couldn't restore stashed changes.${C_RESET} Run 'git stash list' to check -- your files may still be recoverable there."
          fi
        fi
        git add .github
        [ -d scripts/dependabot-autosetup ] && git add scripts/dependabot-autosetup
        if git commit -m "Add Dependabot config and auto-merge workflow"; then
          :
        else
          echo -e "${C_OFF}Nothing new to commit.${C_RESET}"
        fi
        if git push -u origin add-dependabot --force; then
          echo -e "${C_ON}Pushed.${C_RESET}"

          if [ "$HAVE_GH" == "true" ]; then
            echo ""
            echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
            echo ""
            echo -e "${C_LABEL}A pull request merging this into your default branch is the last step to actually activate it.${C_RESET}"
            echo -e "${C_ON}Recommended: yes${C_RESET} -- it's just the generated config files, nothing that needs review."
            read -p "$(echo -e "${C_PROMPT}Create and merge that PR now? [y/n]: ${C_RESET}")" MERGE_ANS
            case "$MERGE_ANS" in
              y|Y)
                CREATE_OUTPUT=$(gh pr create --fill --head add-dependabot --base "$DEFAULT_BRANCH" 2>&1)
                if echo "$CREATE_OUTPUT" | grep -qi -E "commits between|no commits"; then
                  echo -e "${C_ON}Already up to date with $DEFAULT_BRANCH -- nothing new to merge.${C_RESET}"
                else
                  MERGE_OUTPUT=$(gh pr merge add-dependabot --merge --delete-branch 2>&1)
                  if [ $? -eq 0 ]; then
                    echo -e "${C_ON}Merged.${C_RESET}"
                  else
                    # Sometimes the PR is successfully created but merge fails because checks are running
                    # or there are no new commits if gh pr create succeeded but returned a warning.
                    # If create succeeded, we can tell the user. If create failed, show the error.
                    if echo "$CREATE_OUTPUT" | grep -q "github.com"; then
                      echo -e "${C_ON}PR created successfully:${C_RESET} $(echo "$CREATE_OUTPUT" | grep "github.com")"
                      echo -e "${C_WARN}Could not auto-merge yet.${C_RESET} You can merge it manually once checks pass."
                    else
                      echo -e "${C_DANGER}Couldn't auto-merge.${C_RESET}"
                      [ -n "$CREATE_OUTPUT" ] && echo -e "${C_OFF}PR create said: $CREATE_OUTPUT${C_RESET}"
                      echo -e "${C_OFF}Merge said: $MERGE_OUTPUT${C_RESET}"
                      echo "Check the PR on GitHub: https://github.com/${REPO_TARGET}/pulls"
                    fi
                  fi
                fi
                ;;
              *)
                echo -e "${C_OFF}Left the PR open.${C_RESET} https://github.com/${REPO_TARGET}/compare/add-dependabot"
                ;;
            esac
          else
            echo -e "${C_OFF}Open a PR at https://github.com/${REPO_TARGET}/compare/add-dependabot${C_RESET}"
          fi
        else
          echo -e "${C_DANGER}Push failed.${C_RESET} Check the error above."
        fi
        ;;
      *)
        echo -e "${C_OFF}Not pushed.${C_RESET} Run: git add .github scripts/dependabot-autosetup && git commit -m 'Add Dependabot' && git push"
        ;;
    esac
  fi

  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
}

# ================= Uninstall =================
SKIP_AUTO_SETUP=false
uninstall_dependabot() {
  echo ""
  echo -e "${C_WARN}This removes Dependabot's config from this repo.${C_RESET}"
  echo -e "  ${C_HEADER}1)${C_RESET} Remove GitHub config only ${C_OFF}(keeps this tool installed for later)${C_RESET}"
  echo -e "  ${C_HEADER}2)${C_RESET} Remove everything ${C_DANGER}(also deletes this tool's own files -- you'd need to reinstall to use it again)${C_RESET}"
  echo -e "  ${C_HEADER}3)${C_RESET} Cancel"
  read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" UNINSTALL_CHOICE

  case "$UNINSTALL_CHOICE" in
    1|2)
      rm -f .github/dependabot.yml
      rm -f "$WORKFLOW_FILE"
      rmdir .github/workflows 2>/dev/null
      rmdir .github 2>/dev/null

      if [ "$UNINSTALL_CHOICE" == "2" ]; then
        echo -e "${C_WARN}Removing this tool's own files...${C_RESET}"
        rm -rf "$SELF_DIR"
      fi

      if [ -n "$REPO_TARGET" ] && [ "$HAVE_GH" == "true" ]; then
        UNINSTALL_DEFAULT_BRANCH=$(gh repo view "$REPO_TARGET" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
        [ -z "$UNINSTALL_DEFAULT_BRANCH" ] && UNINSTALL_DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#refs/remotes/origin/##')
        [ -n "$UNINSTALL_DEFAULT_BRANCH" ] && git checkout "$UNINSTALL_DEFAULT_BRANCH" 2>/dev/null
        git add -A .github scripts/dependabot-autosetup 2>/dev/null
        if git commit -m "Uninstall dependabot-autosetup"; then
          git push 2>/dev/null
          echo -e "${C_ON}Removed and pushed.${C_RESET}"
          SKIP_AUTO_SETUP=true
        else
          echo -e "${C_OFF}Nothing to remove -- Dependabot wasn't set up here.${C_RESET}"
        fi
      else
        echo -e "${C_OFF}Removed locally. Run: git add -A .github scripts/dependabot-autosetup && git commit -m 'Uninstall dependabot-autosetup' && git push${C_RESET}"
        SKIP_AUTO_SETUP=true
      fi

      if [ "$UNINSTALL_CHOICE" == "2" ]; then
        echo ""
        echo -e "${C_ON}Uninstalled.${C_RESET} This tool's files are gone -- re-run the installer if you need it again."
        exit 0
      fi
      ;;
    *)
      echo -e "${C_OFF}Cancelled.${C_RESET}"
      ;;
  esac
}

# ================= Main loop: status -> auto-setup if missing -> menu -> loop =================
connect_github
refresh_status

while true; do
  show_status

  if [ "$LOCAL_CONFIG" == "false" ] && [ "$GH_CONFIG" == "false" ] && [ "$SKIP_AUTO_SETUP" != "true" ]; then
    echo -e "${C_WARN}Dependabot isn't set up here yet.${C_RESET} Running setup..."
    run_setup
    refresh_status
    continue
  fi

  echo -e "${C_HEADER}Choose an action:${C_RESET}"
  echo -e "  ${C_HEADER}1)${C_RESET} Re-run setup / push changes"
  echo -e "  ${C_HEADER}2)${C_RESET} Push changes (no re-run)"
  echo -e "  ${C_HEADER}3)${C_RESET} Configure features (Auto-Merge, Security Alerts, Visibility)"
  echo -e "  ${C_HEADER}4)${C_RESET} Run Dependabot check & pull updates"
  echo -e "  ${C_HEADER}5)${C_RESET} Uninstall dependabot-autosetup"
  echo -e "  ${C_HEADER}6)${C_RESET} Exit"
  read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" CHOICE

  case $CHOICE in
    1) SKIP_AUTO_SETUP=false; run_setup; refresh_status ;;
    2) push_changes; refresh_status ;;
    3)
      while true; do
        echo ""
        echo -e "${C_HEADER}=== Feature Configuration ===${C_RESET}"
        if [ "$RISK_MODE" == "low" ] || [ "$RISK_MODE" == "all" ]; then LOW_DISP="${C_ON}On${C_RESET}"; else LOW_DISP="${C_OFF}Off${C_RESET}"; fi
        if [ "$RISK_MODE" == "all" ]; then HIGH_DISP="${C_DANGER}On${C_RESET}"; else HIGH_DISP="${C_OFF}Off${C_RESET}"; fi
        if [ "$ALERTS_STATUS" == "on" ]; then ALERT_DISP="${C_ON}On${C_RESET}"; elif [ "$ALERTS_STATUS" == "off" ]; then ALERT_DISP="${C_WARN}Off${C_RESET}"; else ALERT_DISP="${C_OFF}Unknown${C_RESET}"; fi
        if [ "$REPO_VISIBILITY" == "public" ]; then VIS_DISP="${C_WARN}Public${C_RESET}"; elif [ "$REPO_VISIBILITY" == "private" ]; then VIS_DISP="${C_ON}Private${C_RESET}"; else VIS_DISP="${C_OFF}Unknown${C_RESET}"; fi

        echo -e "  ${C_HEADER}1)${C_RESET} Toggle low-risk auto-merge   [Currently: $LOW_DISP]"
        echo -e "  ${C_HEADER}2)${C_RESET} Toggle high-risk auto-merge  [Currently: $HIGH_DISP]"
        echo -e "  ${C_HEADER}3)${C_RESET} Toggle security alert emails [Currently: $ALERT_DISP]"
        echo -e "  ${C_HEADER}4)${C_RESET} Toggle repo visibility       [Currently: $VIS_DISP]"
        echo -e "  ${C_HEADER}5)${C_RESET} Back to main menu"
        read -p "$(echo -e "${C_PROMPT}> ${C_RESET}")" SUB_CHOICE

        case $SUB_CHOICE in
          1)
            if [ "$RISK_MODE" == "low" ] || [ "$RISK_MODE" == "all" ]; then write_workflow "none"; else write_workflow "low"; fi
            echo -e "${C_OFF}Now: git add .github scripts/dependabot-autosetup && git commit -m 'Update Dependabot auto-merge' && git push${C_RESET}"
            refresh_status
            ;;
          2)
            if [ "$RISK_MODE" == "all" ]; then write_workflow "low"; else write_workflow "all"; fi
            echo -e "${C_OFF}Now: git add .github scripts/dependabot-autosetup && git commit -m 'Update Dependabot auto-merge' && git push${C_RESET}"
            refresh_status
            ;;
          3)
            if [ "$HAVE_GH" != "true" ] || [ -z "$REPO_TARGET" ]; then
              echo -e "${C_DANGER}No connected GitHub repo -- can't toggle alerts.${C_RESET}"
            elif [ "$ALERTS_STATUS" == "on" ]; then
              gh api -X DELETE "repos/$REPO_TARGET/vulnerability-alerts" >/dev/null 2>&1 && echo -e "${C_OFF}Turned OFF.${C_RESET}"
            else
              gh api -X PUT "repos/$REPO_TARGET/vulnerability-alerts" >/dev/null 2>&1 && echo -e "${C_ON}Turned ON.${C_RESET}"
            fi
            refresh_status
            ;;
          4)
            if [ "$HAVE_GH" != "true" ] || [ -z "$REPO_TARGET" ]; then
              echo -e "${C_DANGER}No connected GitHub repo -- can't change visibility.${C_RESET}"
            elif [ "$REPO_VISIBILITY" == "public" ]; then
              gh repo edit "$REPO_TARGET" --visibility private --accept-visibility-change-consequences >/dev/null 2>&1 && echo -e "${C_ON}Set to private.${C_RESET}"
            else
              gh repo edit "$REPO_TARGET" --visibility public --accept-visibility-change-consequences >/dev/null 2>&1 && echo -e "${C_WARN}Set to public.${C_RESET}"
            fi
            refresh_status
            ;;
          5) break ;;
          *) echo -e "${C_DANGER}Invalid choice.${C_RESET}" ;;
        esac
      done
      refresh_status
      ;;
    4)
      CURR_BRANCH=$(git branch --show-current)
      echo -e "${C_LABEL}Pulling latest updates from origin...${C_RESET}"
      git fetch origin
      if git pull origin "$CURR_BRANCH"; then
        echo -e "${C_ON}Successfully pulled latest updates to your current local branch '${CURR_BRANCH}'.${C_RESET}"
      else
        echo -e "${C_DANGER}Failed to pull updates.${C_RESET} Please check if you have uncommitted changes or conflicts."
      fi

      if [ "$HAVE_GH" != "true" ] || [ -z "$REPO_TARGET" ]; then
        echo -e "${C_DANGER}No connected GitHub repo -- can't trigger manual update check or view PRs.${C_RESET}"
      else
        echo ""
        echo -e "${C_LABEL}Checking open Dependabot PRs...${C_RESET}"
        # Fetch PR numbers and titles
        # Using a temporary file to read raw data cleanly into an array, keeping stdin completely free of piping
        local TEMP_PR_FILE
        TEMP_PR_FILE=$(mktemp)
        gh pr list --repo "$REPO_TARGET" --author "app/dependabot" --json number,title --jq '.[] | "\(.number):\(.title)"' > "$TEMP_PR_FILE" 2>/dev/null
        
        PR_LINES=()
        if [ -f "$TEMP_PR_FILE" ]; then
          while IFS= read -r line; do
            [ -n "$line" ] && PR_LINES+=("$line")
          done < "$TEMP_PR_FILE"
          rm -f "$TEMP_PR_FILE"
        fi

        if [ ${#PR_LINES[@]} -gt 0 ]; then
          echo -e "${C_ON}Open Dependabot PRs:${C_RESET}"
          for pr_line in "${PR_LINES[@]}"; do
            pr_num="${pr_line%%:*}"
            pr_title="${pr_line#*:}"
            echo -e "  #${pr_num} ${pr_title}"
          done
          echo ""

          read -p "$(echo -e "${C_PROMPT}Would you like to update any of these now? [y/n]: ${C_RESET}")" MERGE_PRS_ANS
          case "$MERGE_PRS_ANS" in
            y|Y)
              for pr_line in "${PR_LINES[@]}"; do
                pr_num="${pr_line%%:*}"
                pr_title="${pr_line#*:}"
                
                # Check update risk type based on PR title patterns (e.g. major version bump vs minor/patch)
                # Matches patterns like: from X.Y.Z to A.B.C where X != A (Major change)
                IS_HIGH_RISK=false
                if echo "$pr_title" | grep -qP "from \d+\..* to \d+\."; then
                  v_from=$(echo "$pr_title" | grep -oP "from \K\d+")
                  v_to=$(echo "$pr_title" | grep -oP "to \K\d+")
                  if [ -n "$v_from" ] && [ -n "$v_to" ] && [ "$v_from" -ne "$v_to" ]; then
                    IS_HIGH_RISK=true
                  fi
                fi

                echo ""
                echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
                if [ "$IS_HIGH_RISK" == "true" ]; then
                  echo -e "${C_DANGER}⚠️ HIGH-RISK UPDATE DETECTED${C_RESET}"
                  echo -e "PR #${pr_num}: \"${pr_title}\""
                  echo "This is a MAJOR version change. It may contain breaking API changes"
                  echo "that require manual code edits to avoid build failures."
                  echo -e "${C_DANGER}Recommendation: n (Review changes carefully before merging.)${C_RESET}"
                else
                  echo -e "${C_ON}✅ LOW-RISK UPDATE DETECTED${C_RESET}"
                  echo -e "PR #${pr_num}: \"${pr_title}\""
                  echo "This is a patch/minor version change. These are intended to be backward-compatible."
                  echo -e "${C_ON}Recommendation: y (Generally safe to merge.)${C_RESET}"
                fi
                echo ""

                read -p "$(echo -e "${C_PROMPT}Would you like to update? [y/n]: ${C_RESET}")" SINGLE_PR_ANS
                case "$SINGLE_PR_ANS" in
                  y|Y)
                    echo -e "${C_OFF}Merging PR #${pr_num}...${C_RESET}"
                    if gh pr merge "$pr_num" --merge --delete-branch >/dev/null 2>&1; then
                      echo -e "${C_ON}Merged PR #${pr_num}.${C_RESET}"
                    else
                      # If direct merge fails (e.g. conflicts), try to checkout and rebase-resolve them
                      echo -e "${C_WARN}Direct merge blocked by conflicts. Attempting local rebase resolution...${C_RESET}"
                      local PREV_BRANCH
                      PREV_BRANCH=$(git branch --show-current)
                      if gh pr checkout "$pr_num" >/dev/null 2>&1; then
                        git fetch origin "$CURR_BRANCH" >/dev/null 2>&1
                        # Rebase using "theirs" strategy (preferring the newer version upgrades)
                        if git rebase -Xtheirs "origin/$CURR_BRANCH" >/dev/null 2>&1; then
                          if git push origin HEAD --force >/dev/null 2>&1; then
                            # Try merging again after clean rebase
                            if gh pr merge "$pr_num" --merge --delete-branch >/dev/null 2>&1; then
                              echo -e "${C_ON}Merged PR #${pr_num} successfully after resolving conflicts.${C_RESET}"
                            else
                              echo -e "${C_DANGER}Failed to merge PR #${pr_num} even after rebase.${C_RESET}"
                            fi
                          else
                            echo -e "${C_DANGER}Failed to push rebased branch for PR #${pr_num}.${C_RESET}"
                          fi
                        else
                          git rebase --abort >/dev/null 2>&1
                          echo -e "${C_DANGER}Conflicts could not be auto-resolved for PR #${pr_num}.${C_RESET}"
                        fi
                        git checkout "$PREV_BRANCH" >/dev/null 2>&1
                      else
                        echo -e "${C_DANGER}Failed to checkout PR #${pr_num} branch.${C_RESET}"
                      fi
                    fi
                    ;;
                esac
              done
              # Pull changes locally if any PRs were merged
              echo -e "${C_LABEL}Pulling latest merged updates to local branch...${C_RESET}"
              git pull origin "$CURR_BRANCH" 2>/dev/null
              ;;
          esac
        else
          echo -e "${C_OFF}No open Dependabot Pull Requests found on GitHub.${C_RESET}"
        fi
        echo ""

        echo -e "${C_LABEL}Triggering Dependabot update checks...${C_RESET}"
        if [ "$LOCAL_CONFIG" == "true" ]; then
          CONFIGURED_ECOS=$(grep "package-ecosystem:" .github/dependabot.yml | awk -F'"' '{print $2}')
          [ -z "$CONFIGURED_ECOS" ] && CONFIGURED_ECOS=$(grep "package-ecosystem:" .github/dependabot.yml | awk '{print $2}' | tr -d '"'\''')
          if [ -n "$CONFIGURED_ECOS" ]; then
            echo -e "${C_OFF}Kicking off check runs on GitHub's servers...${C_RESET}"
            if gh api -X POST "repos/$REPO_TARGET/dependabot/updates/trigger" >/dev/null 2>&1; then
              echo -e "${C_ON}Dependabot updates check runs triggered successfully on GitHub.${C_RESET}"
              echo -e "${C_OFF}Dependabot will check for updates and output PRs/emails in the background.${C_RESET}"
            else
              echo -e "${C_WARN}Dependabot updates API trigger endpoint failed or not active on this repository yet.${C_RESET}"
              echo -e "${C_OFF}Dependabot updates run automatically on push/sync of config. Make sure config has been pushed to GitHub.${C_RESET}"
            fi
          else
            echo -e "${C_DANGER}Could not extract ecosystems from local dependabot.yml.${C_RESET}"
          fi
        else
          echo -e "${C_DANGER}Local dependabot.yml configuration file not found.${C_RESET}"
        fi
      fi
      refresh_status
      ;;
    5) uninstall_dependabot; refresh_status ;;
    6) echo -e "${C_ON}Done.${C_RESET}"; break ;;
    *) echo -e "${C_DANGER}Invalid choice.${C_RESET}" ;;
  esac
done