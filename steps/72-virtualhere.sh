#!/usr/bin/env bash
# 72 — Serveur VirtualHere : partage le volant (Moza) avec le PC de jeu, qui le voit comme branché
# chez lui (client VirtualHere sur le PC). Version gratuite : un appareil partagé à la fois.
source "$REPO_DIR/lib/common.sh"; step_init

BIN=/usr/local/sbin/vhusbdx86_64
CONF_DIR=/usr/local/etc/virtualhere
CONF=$CONF_DIR/config.ini
URL=https://www.virtualhere.com/sites/default/files/usbserver/vhusbdx86_64

if [[ $(uname -m) != x86_64 ]]; then
  warn "VirtualHere : seule la version x86_64 est prévue ici, étape ignorée."
  exit 0
fi

# --- Programme (retéléchargé à chaque mise à jour ; on garde l'ancien si le site ne répond pas) ---
tmp=$(mktemp -d)
if download "$URL" "$tmp/vhusbd" && [[ $(head -c 4 "$tmp/vhusbd" | od -An -tx1 | tr -d ' ') == 7f454c46 ]]; then
  install -m 0755 "$tmp/vhusbd" "$BIN"
  ok "Serveur VirtualHere téléchargé"
elif [[ -x $BIN ]]; then
  warn "VirtualHere : téléchargement impossible, on garde la version déjà installée."
else
  rm -rf "$tmp"
  warn "VirtualHere : téléchargement impossible ($URL). Relance plus tard : sudo ./update.sh --only 72"
  exit 0
fi
rm -rf "$tmp"

# --- Réglages : nom du serveur, et appareils internes jamais partagés -------------------------
# Le serveur écrit lui-même dans config.ini (licence…) : on ne touche qu'à nos clés.
# Tout appareil USB présent à l'installation (Bluetooth, caméra, lecteur d'empreinte…) est exclu,
# sauf les volants Moza (fabricant 346e) : le PC ne pourra pas « emprunter » la manette Bluetooth.
install -d "$CONF_DIR"
[[ -f $CONF ]] || : > "$CONF"
ignored=()
for d in /sys/bus/usb/devices/*; do
  [[ -f $d/idVendor && -f $d/idProduct ]] || continue
  [[ $(cat "$d/bDeviceClass" 2>/dev/null) == 09 ]] && continue          # concentrateurs
  vid=$(cat "$d/idVendor"); pid=$(cat "$d/idProduct")
  [[ $vid == 346e || $vid == 1d6b ]] && continue                         # Moza ; hubs racine
  ignored+=("$vid/$pid")
done
ignored_csv=$(printf '%s\n' "${ignored[@]}" | sort -u | paste -sd, -)
python3 - "$CONF" "ServerName=${CONSOLE_NAME:-console}" "IgnoredDevices=$ignored_csv" <<'PY'
import sys
path, *pairs = sys.argv[1:]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
for pair in pairs:
    key = pair.split("=", 1)[0]
    lines = [l for l in lines if l.split("=", 1)[0].strip() != key]
    if pair.split("=", 1)[1]:
        lines.append(pair)
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
ok "VirtualHere : appareils internes exclus du partage (${ignored_csv:-aucun})"

# --- Service ---------------------------------------------------------------------------------
cat > /etc/systemd/system/virtualhere.service <<EOF
[Unit]
Description=VirtualHere Server (partage du volant avec le PC de jeu)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=$BIN -b -c $CONF
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable virtualhere.service >/dev/null 2>&1
systemctl restart virtualhere.service
ok "Serveur VirtualHere actif (port 7575)"
note "Volant : installe le client VirtualHere sur le PC, puis ajoute la console à la main (adresse Tailscale de la console, port 7575)."
