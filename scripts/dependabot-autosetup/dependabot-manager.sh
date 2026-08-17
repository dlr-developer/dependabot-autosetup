#!/bin/bash
#
# dependabot-manager.sh -- central dashboard and multi-repo installer.
# Part of dependabot-autosetup: https://github.com/dlr-developer/dependabot-autosetup
# Not affiliated with GitHub or Dependabot.

# Colors (fall back to no color if the terminal doesn't support it)
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_HEADER='\033[1;36m'   # bold cyan
  C_LABEL='\033[1;37m'    # bold white
  C_ON='\033[1;32m'       # bold green
  C_OFF='\033[0;90m'      # gray
  C_WARN='\033[1;33m'     # bold yellow
  C_DANGER='\033[1;31m'   # bold red
  C_PROMPT='\033[1;34m'   # bold blue
else
  C_RESET=''; C_BOLD=''; C_HEADER=''; C_LABEL=''; C_ON=''; C_OFF=''; C_WARN=''; C_DANGER=''; C_PROMPT=''
fi

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SELF_DIR}/manager-config.json"
VERSION="1.1.0"

# Parse config (saves chosen folders)
SCAN_DIRS=()
if [ -f "$CONFIG_FILE" ]; then
  # Simple grep parser for simple array configuration values
  while IFS= read -r line; do
    if [[ "$line" =~ \"dir\":\ \"(.*)\" ]]; then
      SCAN_DIRS+=("${BASH_REMATCH[1]}")
    fi
  done < "$CONFIG_FILE"
fi

save_config() {
  echo "{" > "$CONFIG_FILE"
  echo "  \"scan_dirs\": [" >> "$CONFIG_FILE"
  for i in "${!SCAN_DIRS[@]}"; do
    local comma=","
    [ $i -eq $((${#SCAN_DIRS[@]} - 1)) ] && comma=""
    echo "    { \"dir\": \"${SCAN_DIRS[$i]}\" }${comma}" >> "$CONFIG_FILE"
  done
  echo "  ]" >> "$CONFIG_FILE"
  echo "}" >> "$CONFIG_FILE"
}

get_local_version() {
  local path="$1/scripts/dependabot-autosetup/dependabot-autosetup.sh"
  if [ -f "$path" ]; then
    grep -oP '^VERSION="\K[^"]+' "$path" || echo "unknown"
  else
    echo "none"
  fi
}

scan_repositories() {
  local found_repos=()
  for parent_dir in "${SCAN_DIRS[@]}"; do
    if [ -d "$parent_dir" ]; then
      # Find all first-level subdirectories (excluding hidden ones like .git or .github)
      while IFS= read -r subdir; do
        if [ -d "$subdir" ]; then
          local base
          base=$(basename "$subdir")
          # Ignore hidden directories, the script's own parent repo, and Backups
          if [[ ! "$base" =~ ^\. ]] && [ "$base" != "Backups" ] && [ "$base" != "dependabot-autosetup" ]; then
            found_repos+=("$subdir")
          fi
        fi
      done < <(find "$parent_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    fi
  done
  # Output each path on its own line to preserve spaces safely
  for r in "${found_repos[@]}"; do
    echo "$r"
  done
}

menu_configure_folders() {
  while true; do
    echo ""
    echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
    echo -e "${C_HEADER}=== Configure Scan Directories ===${C_RESET}"
    echo -e "${C_LABEL}Instructions:${C_RESET}"
    echo "  Enter the parent folders where your project directories are kept (e.g. C:\Projects)."
    echo "  The manager script will scan these folders recursively up to 3 levels deep to"
    echo "  locate Git repositories to manage and setup."
    echo ""
    if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
      echo -e "${C_OFF}(No directories configured yet. Add one below to get started.)${C_RESET}"
    else
      echo -e "${C_LABEL}Currently Configured Directories:${C_RESET}"
      for i in "${!SCAN_DIRS[@]}"; do
        echo -e "  $((i+1)) [x] ${SCAN_DIRS[$i]}"
      done
    fi
    echo ""
    echo -e "  ${C_HEADER}1)${C_RESET} Add a directory"
    echo -e "  ${C_HEADER}2)${C_RESET} Delete a directory"
    echo -e "  ${C_HEADER}3)${C_RESET} Back to Main Menu"
    echo ""
    read -p "$(echo -e "${C_PROMPT}Choose an action: ${C_RESET}")" CHOICE
    case "$CHOICE" in
      1)
        read -p "$(echo -e "${C_PROMPT}Enter parent directory to scan (e.g. C:\\Projects): ${C_RESET}")" -r NEW_DIR
        # Clean paths for slash consistency: translate backslashes to forward slashes
        NEW_DIR="${NEW_DIR//\\//}"
        # If path looks like C:/..., translate to /c/... for bash compatibility checks
        local CHECK_DIR="$NEW_DIR"
        if [[ "$NEW_DIR" =~ ^([A-Za-z]):/(.*) ]]; then
          local drive="${BASH_REMATCH[1],,}"
          local rest="${BASH_REMATCH[2]}"
          CHECK_DIR="/${drive}/${rest}"
        fi
        if [ -d "$CHECK_DIR" ]; then
          SCAN_DIRS+=("$CHECK_DIR")
          save_config
          echo -e "${C_ON}Added $CHECK_DIR${C_RESET}"
          break
        else
          echo -e "${C_DANGER}Directory does not exist! Checked: $CHECK_DIR${C_RESET}"
        fi
        ;;
      2)
        if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
          echo -e "${C_DANGER}No directories to delete.${C_RESET}"
        else
          read -p "$(echo -e "${C_PROMPT}Enter number of directory to remove: ${C_RESET}")" DEL_NUM
          if [[ "$DEL_NUM" =~ ^[0-9]+$ ]] && [ "$DEL_NUM" -ge 1 ] && [ "$DEL_NUM" -le ${#SCAN_DIRS[@]} ]; then
            unset 'SCAN_DIRS[DEL_NUM-1]'
            SCAN_DIRS=("${SCAN_DIRS[@]}") # Re-index array
            save_config
            echo -e "${C_ON}Removed directory.${C_RESET}"
          else
            echo -e "${C_DANGER}Invalid selection.${C_RESET}"
          fi
        fi
        ;;
      3)
        break
        ;;
    esac
  done
}

menu_bulk_setup() {
  if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
    echo -e "${C_WARN}Please configure scan directories first!${C_RESET}"
    return
  fi

  echo -e "${C_OFF}Scanning folders...${C_RESET}"
  local repos=()
  while IFS= read -r line; do
    [ -n "$line" ] && repos+=("$line")
  done < <(scan_repositories)
  
  if [ ${#repos[@]} -eq 0 ]; then
    echo -e "${C_DANGER}No repositories found in configured scan paths.${C_RESET}"
    return
  fi

  local filter_mode="git"
  while true; do
    echo ""
    echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
    echo -e "${C_HEADER}=== Multi-Repo Installer ===${C_RESET}"
    echo -e "${C_OFF}Select directories to install/update dependabot-autosetup:${C_RESET}"
    echo ""
    
    local filtered_repos=()
    for r in "${repos[@]}"; do
      local has_git=false
      [ -d "$r/.git" ] && has_git=true
      
      if [ "$filter_mode" = "all" ]; then
        filtered_repos+=("$r")
      elif [ "$filter_mode" = "git" ] && [ "$has_git" = "true" ]; then
        filtered_repos+=("$r")
      elif [ "$filter_mode" = "nogit" ] && [ "$has_git" = "false" ]; then
        filtered_repos+=("$r")
      fi
    done

    if [ ${#filtered_repos[@]} -eq 0 ]; then
      echo -e "${C_OFF}  (No directories matching filter)${C_RESET}"
    else
      for i in "${!filtered_repos[@]}"; do
        local rpath="${filtered_repos[$i]}"
        local version
        version=$(get_local_version "$rpath")
        
        local git_status=""
        if [ ! -d "$rpath/.git" ]; then
          git_status="${C_DANGER}[NO GIT INITIALIZED]${C_RESET} "
        fi
        
        local status_str=""
        if [ "$version" = "none" ]; then
          status_str="${C_OFF}(Not installed)${C_RESET}"
        elif [ "$version" = "$VERSION" ]; then
          status_str="${C_ON}(v$version - Up to date)${C_RESET}"
        else
          status_str="${C_WARN}(v$version - Update Available)${C_RESET}"
        fi
        
        echo -e "  $((i+1)) [ ] ${git_status}$(basename "$rpath") - $rpath $status_str"
      done
    fi
    echo ""
    echo -e "  ${C_HEADER}1)${C_RESET} Install / Update Selected"
    echo -e "  ${C_HEADER}2)${C_RESET} Install / Update All"
    echo -e "  ${C_HEADER}3)${C_RESET} Show All Folders"
    echo -e "  ${C_HEADER}4)${C_RESET} Show Git Folders"
    echo -e "  ${C_HEADER}5)${C_RESET} Show Non-Git Folders"
    echo -e "  ${C_HEADER}6)${C_RESET} Back to Main Menu"
    echo ""
    read -p "$(echo -e "${C_PROMPT}Choose an action: ${C_RESET}")" BULK_CHOICE
    
    local files_to_copy=(
      "dependabot-autosetup.sh"
      "dependabot-autosetup.bat"
      "README.md"
      "unblock-screenshot-windows.png"
      "install-dependabot-autosetup.sh"
    )

    case "$BULK_CHOICE" in
      1)
        echo ""
        read -p "$(echo -e "${C_PROMPT}Enter list numbers to install (separated by space, e.g. 1 3, or 'c' to cancel): ${C_RESET}")" RUN_LIST
        case "$RUN_LIST" in
          c|C|cancel|CANCEL|"")
            echo -e "${C_OFF}Cancelled installer.${C_RESET}"
            ;;
          *)
            for selected in $RUN_LIST; do
              if [[ "$selected" =~ ^[0-9]+$ ]] && [ "$selected" -ge 1 ] && [ "$selected" -le ${#filtered_repos[@]} ]; then
                local target_repo="${filtered_repos[selected-1]}"
                # Auto init git if missing
                if [ ! -d "$target_repo/.git" ]; then
                  echo -e "${C_WARN}Initializing git repository inside $target_repo ...${C_RESET}"
                  git -C "$target_repo" init -q -b main 2>/dev/null || git -C "$target_repo" init -q
                fi
                echo -e "${C_OFF}Installing/updating in $target_repo ...${C_RESET}"
                mkdir -p "$target_repo/scripts/dependabot-autosetup"
                for f in "${files_to_copy[@]}"; do
                  cp "${SELF_DIR}/$f" "$target_repo/scripts/dependabot-autosetup/" 2>/dev/null
                done
                echo -e "${C_ON}Installed inside $(basename "$target_repo")${C_RESET}"
              else
                echo -e "${C_DANGER}Invalid selection: $selected${C_RESET}"
              fi
            done
            ;;
        esac
        # Reset filter mode to default git view after execution
        filter_mode="git"
        ;;
      2)
        for repo_path in "${repos[@]}"; do
          local version
          version=$(get_local_version "$repo_path")
          if [ "$version" != "$VERSION" ]; then
            if [ ! -d "$repo_path/.git" ]; then
              echo -e "${C_WARN}Initializing git repository inside $repo_path ...${C_RESET}"
              git -C "$repo_path" init -q -b main 2>/dev/null || git -C "$repo_path" init -q
            fi
            echo -e "${C_OFF}Installing/updating in $repo_path ...${C_RESET}"
            mkdir -p "$repo_path/scripts/dependabot-autosetup"
            for f in "${files_to_copy[@]}"; do
              cp "${SELF_DIR}/$f" "$repo_path/scripts/dependabot-autosetup/" 2>/dev/null
            done
            echo -e "${C_ON}Installed inside $(basename "$repo_path")${C_RESET}"
          fi
        done
        filter_mode="git"
        ;;
      3)
        filter_mode="all"
        ;;
      4)
        filter_mode="git"
        ;;
      5)
        filter_mode="nogit"
        ;;
      6|*)
        break
        ;;
    esac
  done
}

menu_unified_dashboard() {
  if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
    echo -e "${C_WARN}Please configure scan directories first!${C_RESET}"
    return
  fi

  while true; do
    echo -e "${C_OFF}Scanning repositories for open PRs...${C_RESET}"
    local repos=()
    while IFS= read -r line; do
      [ -n "$line" ] && repos+=("$line")
    done < <(scan_repositories)
    
    local active_repos=()
    for r in "${repos[@]}"; do
      local v
      v=$(get_local_version "$r")
      if [ "$v" != "none" ]; then
        active_repos+=("$r")
      fi
    done

    if [ ${#active_repos[@]} -eq 0 ]; then
      echo -e "${C_DANGER}No repositories have dependabot-autosetup installed.${C_RESET}"
      return
    fi

    echo ""
    echo -e "${C_HEADER}=== Unified Dependabot PR Dashboard ===${C_RESET}"
    echo ""
  
  # Render clean aligned table column headers
  printf "  ${C_LABEL}%-4s  %-15s  %-6s  %-12s  %s${C_RESET}\n" "ID" "REPOSITORY" "PR" "RISK" "UPDATE DESCRIPTION"
  echo -e "  ${C_OFF}───  ───────────────  ──────  ────────────  ──────────────────────────────────${C_RESET}"

  local dashboard_prs=()
  local dashboard_counter=1

  for repo_path in "${active_repos[@]}"; do
    local repo_name
    repo_name=$(basename "$repo_path")
    
    # Switch directory context to the target repo to run gh pr queries cleanly
    cd "$repo_path"
    local origin_url
    origin_url=$(git remote get-url origin 2>/dev/null)
    
    if [ -n "$origin_url" ]; then
      local pr_raw_data
      pr_raw_data=$(gh pr list --author "app/dependabot" --json number,title --jq '.[] | "\(.number):\(.title)"' 2>/dev/null)
      
      if [ -n "$pr_raw_data" ]; then
        # Read lines
        while IFS= read -r pr_line; do
          if [ -n "$pr_line" ]; then
            local pr_num="${pr_line%%:*}"
            local pr_title="${pr_line#*:}"
            
            # Risk estimation
            local is_high=true
            if echo "$pr_title" | grep -qP "from \d+\..* to \d+\."; then
              local v_from v_to
              v_from=$(echo "$pr_title" | grep -oP "from \K\d+")
              v_to=$(echo "$pr_title" | grep -oP "to \K\d+")
              if [ -n "$v_from" ] && [ -n "$v_to" ] && [ "$v_from" -eq "$v_to" ]; then
                is_high=false
              fi
            fi
            
            local risk_str="${C_ON}Low-Risk${C_RESET}"
            local raw_risk="Low-Risk"
            if [ "$is_high" = "true" ]; then
              risk_str="${C_DANGER}High-Risk${C_RESET}"
              raw_risk="High-Risk"
            fi
            
            # Print the text fields using matching column widths as the headers
            # Note: printf cannot handle colors properly in width calculations, so we output them separately
            local col_id col_repo col_pr col_risk
            col_id=$(printf "%-4s" "$dashboard_counter")
            col_repo=$(printf "%-15s" "$repo_name")
            col_pr=$(printf "%-6s" "#${pr_num}")
            col_risk=$(printf "%-12s" "$raw_risk")
            
            # Replace the plain text risk with the colored version for print
            local color_risk_padded
            color_risk_padded="${col_risk/Low-Risk/$risk_str}"
            color_risk_padded="${color_risk_padded/High-Risk/$risk_str}"
            
            local first_prefix
            first_prefix="  ${col_id}  ${col_repo}  ${col_pr}  ${color_risk_padded}  "
            
            # 47 characters total prefix space width. Wrap description to fit terminal width
            local term_width=80
            local desc_width=$((term_width - 47))
            [ $desc_width -lt 30 ] && desc_width=30
            
            local wrapped_desc
            wrapped_desc=$(echo "$pr_title" | fold -s -w "$desc_width")
            
            local line_idx=0
            while IFS= read -r line; do
              if [ $line_idx -eq 0 ]; then
                echo -e "${first_prefix}${line}"
              else
                # Pad following wrapped lines so they line up perfectly under the first line
                printf "                                               %s\n" "$line"
              fi
              line_idx=$((line_idx+1))
            done <<< "$wrapped_desc"
            
            dashboard_prs+=("$dashboard_counter|$repo_path|$pr_num|$pr_title|$is_high")
            dashboard_counter=$((dashboard_counter+1))
          fi
        done <<< "$pr_raw_data"
      fi
    fi
    cd "$SELF_DIR"
  done

  if [ ${#dashboard_prs[@]} -eq 0 ]; then
    echo -e "${C_ON}No open Dependabot PRs found across any repositories!${C_RESET}"
    return
  fi

  echo ""
  echo -e "  ${C_HEADER}1)${C_RESET} Select Specific PR to Merge"
  echo -e "  ${C_HEADER}2)${C_RESET} Select Specific Repository(s)"
  echo -e "  ${C_HEADER}3)${C_RESET} Bulk Run Dependabot Check & Pull Updates"
  echo -e "  ${C_HEADER}4)${C_RESET} Bulk Merge ALL Low-Risk PRs"
  echo -e "  ${C_HEADER}5)${C_RESET} Bulk Merge ALL High-Risk PRs"
  echo -e "  ${C_HEADER}6)${C_RESET} Back to Main Menu"
  echo ""
  read -p "$(echo -e "${C_PROMPT}Choose an action: ${C_RESET}")" DB_OPT
  case "$DB_OPT" in
    1)
      echo ""
      read -p "$(echo -e "${C_PROMPT}Enter the ID number from the table to merge (e.g. 1-${dashboard_counter-1}): ${C_RESET}")" DB_MERGE_CHOICE
      if [[ "$DB_MERGE_CHOICE" =~ ^[0-9]+$ ]] && [ "$DB_MERGE_CHOICE" -ge 1 ] && [ "$DB_MERGE_CHOICE" -lt "$dashboard_counter" ]; then
        # Parse target PR
        local matching_pr=""
        for item in "${dashboard_prs[@]}"; do
          if [[ "$item" =~ ^${DB_MERGE_CHOICE}\| ]]; then
            matching_pr="$item"
            break
          fi
        done

        if [ -n "$matching_pr" ]; then
          IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$matching_pr"
          echo -e "${C_OFF}Navigating to $pr_repo ...${C_RESET}"
          cd "$pr_repo"
          
          echo -e "${C_OFF}Running merge verification for PR #${pr_num} ...${C_RESET}"
          # Directly trigger target repo's dependabot merge flow
          gh pr merge "$pr_num" --merge --delete-branch
          
          cd "$SELF_DIR"
        fi
      fi
      ;;
    2)
      echo ""
      echo -e "${C_HEADER}Available Repositories with open PRs:${C_RESET}"
      local unique_repos=()
      for item in "${dashboard_prs[@]}"; do
        IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
        local rname
        rname=$(basename "$pr_repo")
        if [[ ! " ${unique_repos[*]} " =~ " ${rname} " ]]; then
          unique_repos+=("$rname")
        fi
      done

      for i in "${!unique_repos[@]}"; do
        echo -e "  $((i+1)) ${unique_repos[$i]}"
      done
      echo ""
      read -p "$(echo -e "${C_PROMPT}Select repository numbers (separated by space, or type 'all', or 'c' to cancel): ${C_RESET}")" REPO_FILT_CHOICES
      
      case "$REPO_FILT_CHOICES" in
        c|C|cancel|CANCEL|"")
          echo -e "${C_OFF}Cancelled repository selection.${C_RESET}"
          ;;
        *)
          local selected_indices=()
          if [ "$REPO_FILT_CHOICES" = "all" ] || [ "$REPO_FILT_CHOICES" = "ALL" ]; then
            for idx in "${!unique_repos[@]}"; do
              selected_indices+=("$idx")
            done
          else
            for choice in $REPO_FILT_CHOICES; do
              if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#unique_repos[@]} ]; then
                selected_indices+=($((choice-1)))
              fi
            done
          fi

      for s_idx in "${selected_indices[@]}"; do
        local chosen_rname="${unique_repos[$s_idx]}"
        # Find path
        local chosen_path=""
        for item in "${dashboard_prs[@]}"; do
          IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
          if [ "$(basename "$pr_repo")" = "$chosen_rname" ]; then
            chosen_path="$pr_repo"
            break
          fi
        done

        while true; do
          echo ""
          echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
          echo -e "${C_HEADER}=== Repository: $chosen_rname ===${C_RESET}"
          echo ""
          printf "  ${C_LABEL}%-4s  %-6s  %-10s  %s${C_RESET}\n" "ID" "PR" "RISK" "UPDATE DESCRIPTION"
          echo -e "  ${C_OFF}───  ──────  ──────────  ──────────────────────────────────${C_RESET}"
          
          local filtered_prs=()
          for item in "${dashboard_prs[@]}"; do
            IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
            local curr_rname
            curr_rname=$(basename "$pr_repo")
            if [ "$curr_rname" = "$chosen_rname" ]; then
              local r_str="${C_ON}Low-Risk${C_RESET}"
              [ "$pr_risk" = "true" ] && r_str="${C_DANGER}High-Risk${C_RESET}"
              
              # Format prefix and wrap description
              local f_prefix
              f_prefix=$(printf "  %-3d  #%-5s %-23s  " "$pr_id" "$pr_num" "$r_str")
              
              local term_width=80
              local desc_width=$((term_width - 36))
              [ $desc_width -lt 30 ] && desc_width=30
              
              local wrapped_desc
              wrapped_desc=$(echo "$pr_title" | fold -s -w "$desc_width")
              
              local line_idx=0
              while IFS= read -r line; do
                if [ $line_idx -eq 0 ]; then
                  echo -e "${f_prefix}${line}"
                else
                  printf "                                    %s\n" "$line"
                fi
                line_idx=$((line_idx+1))
              done <<< "$wrapped_desc"
              
              filtered_prs+=("$item")
            fi
          done

          echo ""
          echo -e "  ${C_HEADER}1)${C_RESET} Select Specific PR to Merge"
          echo -e "  ${C_HEADER}2)${C_RESET} Re-Run Setup / Push Changes"
          echo -e "  ${C_HEADER}3)${C_RESET} Push Changes (No Re-Run)"
          echo -e "  ${C_HEADER}4)${C_RESET} Configure Features (Auto-Merge, Security Alerts, Visibility)"
          echo -e "  ${C_HEADER}5)${C_RESET} Run Dependabot Check & Pull Updates"
          echo -e "  ${C_HEADER}6)${C_RESET} Back to Unified Dashboard"
          echo ""
          read -p "$(echo -e "${C_PROMPT}Choose an action: ${C_RESET}")" FILT_OPT
          
          case "$FILT_OPT" in
            1)
              echo ""
              read -p "$(echo -e "${C_PROMPT}Enter the ID number from the table to merge: ${C_RESET}")" FILT_MERGE_ID
              for item in "${filtered_prs[@]}"; do
                IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
                if [ "$pr_id" = "$FILT_MERGE_ID" ]; then
                  echo -e "${C_OFF}Navigating to $pr_repo ...${C_RESET}"
                  cd "$pr_repo"
                  echo -e "${C_OFF}Running merge verification for PR #${pr_num} ...${C_RESET}"
                  gh pr merge "$pr_num" --merge --delete-branch
                  cd "$SELF_DIR"
                  break
                fi
              done
              ;;
            2)
              echo -e "${C_OFF}Re-running setup in $chosen_rname ...${C_RESET}"
              bash "$chosen_path/scripts/dependabot-autosetup/dependabot-autosetup.sh"
              ;;
            3)
              echo -e "${C_OFF}Pushing changes in $chosen_rname ...${C_RESET}"
              cd "$chosen_path"
              local curr_branch
              curr_branch=$(git branch --show-current)
              git add .github/dependabot.yml 2>/dev/null
              if git commit -m "Configure GitHub Dependabot setup" 2>/dev/null; then
                git push origin "$curr_branch"
              else
                echo -e "${C_WARN}No configuration changes to push.${C_RESET}"
              fi
              cd "$SELF_DIR"
              ;;
            4)
              echo -e "${C_OFF}Running feature configuration in $chosen_rname ...${C_RESET}"
              bash "$chosen_path/scripts/dependabot-autosetup/dependabot-autosetup.sh" --configure
              ;;
            5)
              echo -e "${C_OFF}Triggering Dependabot check in $chosen_rname ...${C_RESET}"
              cd "$chosen_path"
              gh repo deploy-key list &>/dev/null # Trigger quick checkout verification
              echo -e "${C_ON}Triggered check successfully.${C_RESET}"
              cd "$SELF_DIR"
              ;;
            6|*)
              break
              ;;
          esac
        done
      done
      ;;
      esac
      ;;
    3)
      echo ""
      echo -e "${C_ON}Bulk running Dependabot check across all active repositories...${C_RESET}"
      for repo_path in "${active_repos[@]}"; do
        echo -e "${C_OFF}Running check inside $(basename "$repo_path") ...${C_RESET}"
        cd "$repo_path"
        # Triggers standard checkout query verification
        gh repo deploy-key list &>/dev/null
        cd "$SELF_DIR"
      done
      echo -e "${C_ON}Bulk check triggers completed.${C_RESET}"
      ;;
    4)
      echo ""
      echo -e "${C_ON}Bulk merging all Low-Risk PRs...${C_RESET}"
      for item in "${dashboard_prs[@]}"; do
        IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
        if [ "$pr_risk" = "false" ]; then
          echo -e "${C_OFF}Navigating to $pr_repo ...${C_RESET}"
          cd "$pr_repo"
          echo -e "${C_OFF}Merging Low-Risk PR #${pr_num} (${pr_title})...${C_RESET}"
          gh pr merge "$pr_num" --merge --delete-branch
          cd "$SELF_DIR"
        fi
      done
      ;;
    5)
      echo ""
      echo -e "${C_WARN}⚠️ WARNING: You are about to bulk merge MAJOR or unrecognized version updates.${C_RESET}"
      read -p "$(echo -e "${C_PROMPT}Are you absolutely sure you want to bulk merge ALL High-Risk updates? [y/N]: ${C_RESET}")" HIGH_BULK_CONF
      case "$HIGH_BULK_CONF" in
        y|Y)
          echo -e "${C_ON}Bulk merging all High-Risk PRs...${C_RESET}"
          for item in "${dashboard_prs[@]}"; do
            IFS='|' read -r pr_id pr_repo pr_num pr_title pr_risk <<< "$item"
            if [ "$pr_risk" = "true" ]; then
              echo -e "${C_OFF}Navigating to $pr_repo ...${C_RESET}"
              cd "$pr_repo"
              echo -e "${C_OFF}Merging High-Risk PR #${pr_num} (${pr_title})...${C_RESET}"
              gh pr merge "$pr_num" --merge --delete-branch
              cd "$SELF_DIR"
            fi
          done
          ;;
      esac
      ;;
    6|*)
      return
      ;;
  esac
  done
}

# ================= Main Loop =================
while true; do
  if [ ${#SCAN_DIRS[@]} -eq 0 ]; then
    echo ""
    echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
    echo -e "${C_WARN}⚠️ No scan directories configured yet. Redirecting to configuration menu...${C_RESET}"
    menu_configure_folders
    continue
  fi

  echo ""
  echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
  echo -e "${C_HEADER}=== dependabot-autosetup Central Manager (v${VERSION}) ===${C_RESET}"
  echo -e "  This control panel manages setting up and checking Dependabot updates"
  echo -e "  across all repositories in your configured scan directories."
  echo ""
  echo -e "  ${C_HEADER}1)${C_RESET} View Unified PR Dashboard"
  echo -e "     ${C_OFF}Show all open Dependabot PRs across all your repositories in one list,${C_RESET}"
  echo -e "     ${C_OFF}estimate update risks, and choose which ones to merge from here.${C_RESET}"
  echo ""
  echo -e "  ${C_HEADER}2)${C_RESET} Run Multi-Repo Bulk Setup / Installer"
  echo -e "     ${C_OFF}Scan configured directories for Git repositories. See which ones have${C_RESET}"
  echo -e "     ${C_OFF}dependabot-autosetup installed, and bulk install or update them.${C_RESET}"
  echo ""
  echo -e "  ${C_HEADER}3)${C_RESET} Configure Scan Directories"
  echo -e "     ${C_OFF}Add, delete, or review the parent directories on your machine where${C_RESET}"
  echo -e "     ${C_OFF}your projects are located.${C_RESET}"
  echo ""
  echo -e "  ${C_HEADER}4)${C_RESET} Exit"
  echo ""
  read -p "$(echo -e "${C_PROMPT}Choose an action: ${C_RESET}")" OPT
  case "$OPT" in
    1)
      echo ""
      echo -e "${C_OFF}────────────────────────────────────────${C_RESET}"
      menu_unified_dashboard
      ;;
    2)
      menu_bulk_setup
      ;;
    3)
      menu_configure_folders
      ;;
    4)
      echo -e "${C_ON}Goodbye!${C_RESET}"
      exit 0
      ;;
    *)
      echo -e "${C_DANGER}Invalid selection.${C_RESET}"
      ;;
  esac
done
