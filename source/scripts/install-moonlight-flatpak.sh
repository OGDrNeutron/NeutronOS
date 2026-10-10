#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Moonlight installation must run as root." >&2
  exit 1
fi

echo "Installing Flatpak support…"
apt-get -y install flatpak ca-certificates cage
echo "Configuring Flathub…"
flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
echo "Installing Moonlight…"
flatpak install --system -y flathub com.moonlight_stream.Moonlight
echo "Moonlight installation complete."
