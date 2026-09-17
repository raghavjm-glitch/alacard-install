#!/usr/bin/env bash
# Puts a kiosk back to "old web version, never upgraded" — for rehearsing a
# remote upgrade on the test machine again and again.
#
# Removes everything the Flutter install added. Keeps Ubuntu, AnyDesk, the
# printer drivers, CUPS and the shop's network. Reboot afterwards.
#
#   wget -4 -T 20 -t 2 -q --header='Accept: application/vnd.github.raw' -O /tmp/reset-to-web.sh https://api.github.com/repos/raghavjm-glitch/alacard-install/contents/reset-to-web.sh && bash /tmp/reset-to-web.sh
set -u
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }

bold "1. Stop the new app"
pkill -f alacard_kiosk 2>/dev/null && ok "closed the running app" || note "app was not running"
pkill -f alacard-keeper 2>/dev/null || true

bold "2. Web kiosk back on boot"
PARKED="$HOME/.alacard-web-kiosk-parked"
mkdir -p "$HOME/.config/autostart"
if [ -d "$PARKED" ] && ls "$PARKED"/*.desktop >/dev/null 2>&1; then
  cp -f "$PARKED"/*.desktop "$HOME/.config/autostart/" && ok "Firefox autostart restored"
  rm -rf "$PARKED"
else
  note "nothing parked — this machine never had the web kiosk switched off"
fi
rm -f "$HOME/.config/autostart/alacard-kiosk.desktop" \
      "$HOME/.config/autostart/alacard-rotate.desktop" && ok "new app will not start on boot"

bold "3. Timers off (updates, diary)"
for t in alacard-update alacard-diary; do
  systemctl --user disable --now "$t.timer" >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/$t.timer" "$HOME/.config/systemd/user/$t.service"
done
systemctl --user daemon-reload 2>/dev/null || true
ok "auto-update and diary timers removed"

bold "4. Print service back to the shop's original"
PD="$HOME/hardware-driver/printer"
OLDEST="$(ls -1 "$PD"/printer.py.backup-* 2>/dev/null | sort | head -1)"
if [ -n "$OLDEST" ]; then
  cp -f "$OLDEST" "$PD/printer.py" && rm -f "$PD"/printer.py.backup-* && ok "restored original printer.py"
  sudo systemctl restart printer.service 2>/dev/null || true
else
  note "no backup of the original printer.py — leaving the print service as it is"
fi
sudo rm -f /etc/sudoers.d/alacard-cups /etc/alacard-printer.conf
sudo nmcli con delete printer-wire >/dev/null 2>&1 && ok "printer-wire network removed" || note "no printer-wire network"

bold "5. Files the install added"
rm -rf "$HOME/alacard" "$HOME/kiosk-new" "$HOME/.local/state/alacard" \
       "$HOME/.config/alacard" "$HOME/.config/rclone" \
       "$HOME/.local/bin/alacard-update.sh" "$HOME/.local/bin/alacard-keeper.sh" "$HOME/.local/bin/alacard-start.sh" \
       "$HOME/.local/share/applications/alacard-kiosk.desktop" "$HOME/.local/share/icons/alacard.png"
rm -rf "$HOME"/.local/share/*alacard* 2>/dev/null
sudo rm -f /etc/alacard-update.conf /etc/X11/xorg.conf.d/99-alacard-touch.conf
ok "app, settings, saved cards, shelf key and diary key removed"

# A machine that was built from source on launch day still holds the source
# and Flutter. A shop kiosk never should.
for d in $(find "$HOME" -maxdepth 3 -name pubspec.yaml 2>/dev/null); do
  if grep -q '^name: alacard_kiosk' "$d" 2>/dev/null; then
    rm -rf "$(dirname "$d")" && ok "removed source folder $(dirname "$d")"
  fi
done
[ -d /opt/flutter ] && sudo rm -rf /opt/flutter && ok "removed Flutter"
[ -d "$HOME/flutter" ] && rm -rf "$HOME/flutter" && ok "removed Flutter"
snap list cmake >/dev/null 2>&1 && sudo snap remove cmake >/dev/null 2>&1 && ok "removed cmake"
sudo rm -f /usr/local/bin/cmake

bold "Kept: AnyDesk, printer drivers, CUPS, wifi, login. Now:  sudo reboot"
