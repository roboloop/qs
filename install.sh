#!/usr/bin/env bash

set -euo pipefail

QS_DIR="$HOME/.qs"
TAG=$(curl -sL https://api.github.com/repos/roboloop/qs/releases/latest | grep tag_name| cut -d '"' -f4)
GITHUB_URL="https://github.com/roboloop/qs/archive/refs/tags/$TAG.tar.gz"

echo "Installing to ${QS_DIR} directory..."
mkdir -p "$QS_DIR"

echo "Downloading the file from ${GITHUB_URL}..."
curl -sL "${GITHUB_URL}" -o "${QS_DIR}/$TAG.tar.gz"

echo "Extracting files..."
tar --strip-components=1 -xf "${QS_DIR}/$TAG.tar.gz" --directory "${QS_DIR}"
rm "${QS_DIR}/$TAG.tar.gz"
chmod +x "${QS_DIR}/qs"

echo "Installation complete!"
echo

message=$(cat <<EOF
To make the 'qs' command globally available, add the following line to your shell configuration file:

  export PATH="\$HOME/.qs:\$PATH"

For:
  Bash    -> ~/.bashrc or ~/.bash_profile
  Zsh     -> ~/.zshrc
  Fish    -> ~/.config/fish/config.fish (use 'set -U fish_user_paths \$HOME/.qs \$fish_user_paths')

Reload your shell configuration file or restart your terminal to apply changes
EOF
)

echo "$message"
