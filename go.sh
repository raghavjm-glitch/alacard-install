#!/usr/bin/env bash
# The one command that installs or upgrades a kiosk.
#
#   wget -4 -T 20 -t 2 -q --header='Accept: application/vnd.github.raw' -O /tmp/go.sh https://api.github.com/repos/raghavjm-glitch/alacard-install/contents/go.sh && bash /tmp/go.sh || echo "COULD NOT DOWNLOAD THE INSTALL SCRIPT — check the internet and paste the command again"
#
# This file is PUBLIC on purpose, so a fresh machine can fetch it with no
# key. It contains no secrets and no source. It asks for the kiosk's shelf
# key once, saves it, downloads the finished program from the private shelf,
# and hands over to the setup that came inside the package. Everything of
# value is behind the key.
set -eu

SHELF_REPO="raghavjm-glitch/alacard-kiosk-builds"
CHANNEL="${CHANNEL:-test}"
KEY_FILE="$HOME/.config/alacard/shelf-key"

b()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
no() { printf '  \033[31m✗\033[0m %s\n' "$*"; }

b "Alacard kiosk — install"

# The password, once, now — not at some unpredictable moment ten minutes in,
# possibly twice, possibly after the person has looked away and sudo's
# five-minute prompt has timed out and taken the rest of the install with
# it (Santa Cruz, 2026-09-17). Kept alive in the background for the whole
# run; the helper dies with this script.
printf '  This needs the kiosk password once.\n'
sudo -v || { no "wrong password, or no sudo for this user"; exit 1; }
( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null' EXIT

# Ubuntu's own updater may be holding the package system when this starts
# (apt-daily, unattended-upgrades). Wait for it rather than trip over it —
# a minute or two, then say so and carry on; the setup will try apt again.
apt_busy() { sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock >/dev/null 2>&1; }
if apt_busy; then
  printf '  Ubuntu is busy with its own updates — waiting for it'
  for _ in $(seq 1 24); do apt_busy || break; printf '.'; sleep 5; done
  echo
fi

# Tools first. The very first launch stopped here because the machine had
# neither curl nor unzip and the old command needed both before it could
# install anything. apt, never snap.
need_tools() { ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; }
if need_tools; then
  b "Installing the tools this needs (curl, unzip, python3)"
  # "|| true" on the update as well as the install: under set -e a failing
  # apt-get update ended the script right here, before the repair below
  # could run — which is precisely the case the repair exists for.
  sudo apt-get update -qq || true; sudo apt-get install -y -qq curl unzip python3 >/dev/null || true
  # A kiosk in Mumbai had a corrupted package list ("Malformed
  # Description-md5 line"); apt refused everything, curl never arrived, and
  # the script went on to blame the key. Clear the lists and try once more.
  if need_tools; then
    echo "  package list looks damaged — clearing it and trying again"
    sudo rm -rf /var/lib/apt/lists/* || true
    sudo apt-get update -qq || true; sudo apt-get install -y -qq curl unzip python3 >/dev/null || true
  fi
  need_tools && { no "could not install curl/unzip/python3 — the internet or Ubuntu's package server is not reachable from here"; exit 1; }
fi
ok "tools present"

# The key. Typed once, over AnyDesk or by the person setting the machine up.
mkdir -p "$(dirname "$KEY_FILE")"
KEY="$(cat "$KEY_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
if [ -z "$KEY" ]; then
  # Asked on the terminal itself, and asked again on an empty answer: a
  # pasted command brings its own Enter, and the Enter typed after it landed
  # here as "no key". Test CPU, 2026-09-17.
  for _ in 1 2 3; do
    printf '\n  Paste this kiosk'"'"'s shelf key and press Enter: '
    read -rs KEY < /dev/tty; echo
    KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
    [ -n "$KEY" ] && break
  done
  [ -n "$KEY" ] || { no "no key given"; exit 1; }
  printf '%s\n' "$KEY" > "$KEY_FILE"; chmod 600 "$KEY_FILE"
fi
API="https://api.github.com/repos/$SHELF_REPO"
# Every small fetch gets a clock; a shop line that answers and then says
# nothing must not hang this for ever.
T="--connect-timeout 15 --max-time 60"
CODE="$(curl -sS $T -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $KEY" "$API" 2>/dev/null || echo 000)"
if [ "$CODE" = 401 ] || [ "$CODE" = 403 ] || [ "$CODE" = 404 ]; then
  no "the key does not open the shelf — check it and run this again"
  rm -f "$KEY_FILE"; exit 1
elif [ "$CODE" != 200 ]; then
  # Not the key's fault: the shelf did not answer. Keep the key; say so.
  no "could not reach the shelf (HTTP $CODE) — check the internet and run this again"
  exit 1
fi
ok "key accepted"

# Which version the channel points at.
b "Finding the current build ($CHANNEL)"
VERSION="$(curl -fsS $T -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github.raw" \
            "$API/contents/$CHANNEL.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])')"
[ -n "$VERSION" ] || { no "could not read the channel"; exit 1; }
ok "build $VERSION"

# Download the finished program (the zip, which unpacks into a named folder).
b "Downloading"
ZIP="alacard-kiosk-$VERSION.zip"
ID="$(curl -fsS $T -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github+json" \
        "$API/releases/tags/v$VERSION" \
      | python3 -c "import sys,json; a=[x for x in json.load(sys.stdin)['assets'] if x['name']=='$ZIP']; print(a[0]['id'] if a else '')")"
[ -n "$ID" ] || { no "build $VERSION has no package on the shelf"; exit 1; }
rm -rf "$HOME/kiosk-new" && mkdir -p "$HOME/kiosk-new"
# Two doors. The release asset lives on GitHub's file server, which some
# Indian ISPs quietly block — Raghav's shop sat at 0 bytes for minutes on
# 2026-09-17. A copy of every build is also committed into the shelf repo,
# and that copy comes through api.github.com, which those ISPs do allow.
# Try the first door for at most 30 seconds of silence, then use the second.
rm -f /tmp/k.zip
if curl -fL --connect-timeout 15 --speed-limit 1000 --speed-time 30 \
     -H "Authorization: Bearer $KEY" -H "Accept: application/octet-stream" \
     -o /tmp/k.zip "$API/releases/assets/$ID"; then
  ok "downloaded"
else
  echo "  the direct download is not getting through here — using the other route"
  rm -f /tmp/k.zip
  curl -fL --connect-timeout 15 --speed-limit 1000 --speed-time 60 \
     -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github.raw" \
     -o /tmp/k.zip "$API/contents/builds/$ZIP" \
    || { no "could not download build $VERSION by either route"; exit 1; }
  ok "downloaded (via api.github.com)"
fi
unzip -q /tmp/k.zip -d "$HOME/kiosk-new"
ok "unpacked"

# The diary key and a current rclone come from the shelf inside the setup
# (setup-kiosk.sh, step 8), which the self-updater re-runs after every
# build — so a replaced key or a newer rclone reaches every kiosk by
# itself. Nothing to do here.

# Hand over. switch-from-web parks the old browser kiosk if there is one and
# then runs the normal setup; on a machine with no old kiosk it just sets up.
cd "$HOME/kiosk-new/alacard-kiosk-$VERSION"
if [ -f kiosk-setup/switch-from-web.sh ]; then
  bash kiosk-setup/switch-from-web.sh
else
  bash kiosk-setup/kiosk.sh
fi
