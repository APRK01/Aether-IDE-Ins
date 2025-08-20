#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Aether Uninstaller (TUI)
# ==============================
# - Quits Aether if running
# - Removes /Applications/Aether.app
# - Optionally removes user data in ~/Library
# - Fancy banner, colors, and spinners

APP_NAME="Aether"
APP_BUNDLE="/Applications/${APP_NAME}.app"

# -------- Colors & UI helpers --------
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  BOLD="$(tput bold)"; DIM="$(tput dim)"; NORM="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"; BLUE="$(tput setaf 4)"
else
  BOLD=""; DIM=""; NORM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; BLUE=""
fi

banner() {
  cat <<'ASCII'
 █████╗ ███████╗████████╗██╗  ██╗███████╗██████╗ 
██╔══██╗██╔════╝╚══██╔══╝██║  ██║██╔════╝██╔══██╗
███████║█████╗     ██║   ███████║█████╗  ██████╔╝
██╔══██║██╔══╝     ██║   ██╔══██║██╔══╝  ██╔══██╗
██║  ██║███████╗   ██║   ██║  ██║███████╗██║  ██║
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
                                                 
ASCII
}

log_step() { echo "${BOLD}${CYAN}▶${NORM} $*"; }
log_info() { echo "${DIM}•${NORM} $*"; }
log_ok()   { echo "${GREEN}✓${NORM} $*"; }
log_warn() { echo "${YELLOW}!${NORM} $*"; }
log_err()  { echo "${RED}✗${NORM} $*"; }

# Platypus-compatible lines (if ever wrapped)
status() { echo "STATUS: $*"; }
progress() { echo "PROGRESS: $1"; }

spinner_run() {
  # spinner_run "Message..." -- command args...
  local msg="$1"; shift
  local frames='|/-\\' i=0 pid
  ( "$@" ) & pid=$!
  printf "  %s %s" "${DIM}${frames:i++%4:1}${NORM}" "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s" "${DIM}${frames:i++%4:1}${NORM}" "$msg"
    sleep 0.1
  done
  if wait "$pid"; then
    printf "\r  %s %s\n" "${GREEN}✓${NORM}" "$msg"
  else
    printf "\r  %s %s\n" "${RED}✗${NORM}" "$msg"
    return 1
  fi
}

require_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_info "Requesting administrator privileges..."
    sudo -v
    exec sudo -E -- "$0" "$@"
  fi
}

main() {
  clear 2>/dev/null || true
  banner
  echo "${BOLD}${BLUE}${APP_NAME} Uninstaller${NORM}"
  echo

  status "Starting ${APP_NAME} Uninstaller"
  progress 1

  if [[ ! -d "${APP_BUNDLE}" ]]; then
    log_warn "${APP_NAME} is not installed in /Applications."
  else
    log_info "Found ${APP_BUNDLE}"
  fi

  # Confirm
  read -r -p "Do you want to uninstall ${APP_NAME}? [y/N]: " ans || true
  case "${ans:-}" in
    y|Y|yes|YES) : ;; 
    *) log_info "Uninstall cancelled."; exit 0;;
  esac

  require_sudo "$@"

  progress 10
  # Try to quit app nicely
  status "Quitting ${APP_NAME} if running..."
  spinner_run "Sending quit signal..." /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" || true
  sleep 1
  spinner_run "Killing remaining processes (if any)..." /usr/bin/pkill -f "${APP_NAME}\.app" || true

  progress 30
  # Remove app bundle
  if [[ -d "${APP_BUNDLE}" ]]; then
    status "Removing ${APP_BUNDLE}..."
    spinner_run "Deleting app bundle..." /bin/rm -rf "${APP_BUNDLE}"
  else
    log_info "App bundle not found, skipping removal."
  fi

  progress 60
  # Ask about user data
  echo
  read -r -p "Remove user data (settings, caches, logs)? [y/N]: " wipe || true
  case "${wipe:-}" in y|Y|yes|YES) DO_WIPE=1 ;; *) DO_WIPE=0 ;; esac

  if [[ "${DO_WIPE}" -eq 1 ]]; then
    status "Removing user data..."
    # Common Electron app directories
    USER_DIRS=(
      "$HOME/Library/Application Support/${APP_NAME}"
      "$HOME/Library/Caches/${APP_NAME}"
      "$HOME/Library/Logs/${APP_NAME}"
      "$HOME/Library/Preferences/com.${APP_NAME,,}.app.plist"
      "$HOME/Library/Preferences/${APP_NAME}.plist"
    )
    for p in "${USER_DIRS[@]}"; do
      if [[ -e "$p" ]]; then
        spinner_run "Deleting $(basename "$p")..." /bin/rm -rf "$p"
      fi
    done
  fi

  progress 90
  log_ok "${APP_NAME} has been uninstalled."
  status "${APP_NAME} uninstalled"
  progress 100
}

main "$@"
