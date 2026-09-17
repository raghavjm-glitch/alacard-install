# Alacard kiosk installer

One line, on the kiosk:

    wget -4 -T 20 -t 2 -q --header='Accept: application/vnd.github.raw' -O /tmp/go.sh https://api.github.com/repos/raghavjm-glitch/alacard-install/contents/go.sh && bash /tmp/go.sh

It asks for the kiosk's key once and does the rest. Everything it installs
comes from a private shelf that needs that key.


Why `api.github.com` and not `raw.githubusercontent.com`: from some Indian
ISPs `raw.githubusercontent.com` hangs while `api.github.com` answers. Found on
the office test CPU, 2026-09-17.
