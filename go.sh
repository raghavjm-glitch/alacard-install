#!/usr/bin/env bash
# The one command that installs or upgrades a kiosk.
#
#   wget -4 -T 20 -t 2 -q --header='Accept: application/vnd.github.raw' -O /tmp/go.sh https://api.github.com/repos/raghavjm-glitch/alacard-install/contents/go.sh && bash /tmp/go.sh
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

# Tools first. The very first launch stopped here because the machine had
# neither curl nor unzip and the old command needed both before it could
# install anything. apt, never snap.
if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  b "Installing the tools this needs (curl, unzip, python3)"
  sudo apt-get update -qq && sudo apt-get install -y -qq curl unzip python3 >/dev/null
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
if ! curl -fsS -H "Authorization: Bearer $KEY" "$API" >/dev/null 2>&1; then
  no "the key does not open the shelf — check it and run this again"
  rm -f "$KEY_FILE"; exit 1
fi
ok "key accepted"

# Which version the channel points at.
b "Finding the current build ($CHANNEL)"
VERSION="$(curl -fsS -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github.raw" \
            "$API/contents/$CHANNEL.json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["version"])')"
[ -n "$VERSION" ] || { no "could not read the channel"; exit 1; }
ok "build $VERSION"

# Download the finished program (the zip, which unpacks into a named folder).
b "Downloading"
ZIP="alacard-kiosk-$VERSION.zip"
ID="$(curl -fsS -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github+json" \
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

# The diary's link to Drive, if the shelf holds one.
#
# Linking a kiosk to Drive otherwise needs a Google sign-in on that machine,
# which cannot be done for twenty-five kiosks over AnyDesk. The office
# kiosk's link works on every kiosk (one Drive, one folder), so it is kept
# on the private shelf and delivered here. Absent → the setup says so and
# the kiosk simply has no diary until it is added.
RC="$HOME/.config/rclone/rclone.conf"
if [ ! -f "$RC" ]; then
  mkdir -p "$(dirname "$RC")"
  if curl -fsS -o "$RC" -H "Authorization: Bearer $KEY" -H "Accept: application/vnd.github.raw" \
       "$API/contents/diary/rclone.conf" 2>/dev/null && [ -s "$RC" ]; then
    chmod 600 "$RC"; ok "diary key installed"
  else
    rm -f "$RC"; printf '  \033[33m!\033[0m %s\n' "no diary key on the shelf yet — the diary will not sync until one is added"
  fi
fi

# Hand over. switch-from-web parks the old browser kiosk if there is one and
# then runs the normal setup; on a machine with no old kiosk it just sets up.
cd "$HOME/kiosk-new/alacard-kiosk-$VERSION"
if [ -f kiosk-setup/switch-from-web.sh ]; then
  bash kiosk-setup/switch-from-web.sh
else
  bash kiosk-setup/kiosk.sh
fi
