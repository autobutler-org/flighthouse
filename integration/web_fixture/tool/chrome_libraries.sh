#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  apt_get=(apt-get)
else
  apt_get=(sudo apt-get)
fi

"${apt_get[@]}" update
packages=(
  ca-certificates
  fonts-liberation
  libatk-bridge2.0-0
  libatk1.0-0
  libdrm2
  libgbm1
  libnss3
  libxcomposite1
  libxdamage1
  libxfixes3
  libxkbcommon0
  libxrandr2
  unzip
  xdg-utils
)
add_first() {
  for candidate in "$@"; do
    if apt-cache show "$candidate" >/dev/null 2>&1; then
      packages+=("$candidate")
      return
    fi
  done
}
add_first libasound2t64 libasound2
add_first libcairo2
add_first libcups2t64 libcups2
add_first libgtk-3-0t64 libgtk-3-0
add_first libpango-1.0-0
"${apt_get[@]}" install -y --no-install-recommends "${packages[@]}"
