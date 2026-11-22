#!/usr/bin/env bash
# Link these dotfiles into $HOME. Existing files are moved to ~/.dotfiles-backup/<timestamp>/.
# Safe to re-run.
#
#   ./install.sh              link configs only
#   ./install.sh --packages   also install packages (pacman + AUR via yay) first
set -euo pipefail
DOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

LINKS=(
    .config/hypr
    .config/caelestia
    .config/foot
    .config/fish
    .config/fastfetch
    .config/mpv
    .config/btop
    .config/starship.toml
    .local/bin/yt
    .local/bin/power-mode-watch
    .local/share/caelestia-github-tab
    .config/quickshell/wallfx
    .local/bin/wallfx
    .local/bin/wallset
    .local/bin/namebanner
    .config/systemd/user/wallfx-watch.path
    .config/systemd/user/wallfx-watch.service
)

if [[ ${1:-} == --packages ]]; then
    step "Installing packages"
    sudo pacman -S --needed - < <(comm -12 <(pacman -Slq | sort -u) <(sort -u "$DOT/packages/pacman.txt"))
    if command -v yay >/dev/null; then
        yay -S --needed - < "$DOT/packages/aur.txt"
    else
        echo "yay not found; install it, then: yay -S --needed - < packages/aur.txt"
    fi
fi

step "Building surfetch"
if command -v go >/dev/null; then
    (cd "$DOT/surfetch" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$HOME/.local/bin/surfetch" .) \
        && echo "  built   ~/.local/bin/surfetch"
else
    echo "  skipped (install go to build surfetch)"
fi

step "Linking configs"
for rel in "${LINKS[@]}"; do
    src="$DOT/$rel"; dst="$HOME/$rel"
    if [[ -L $dst && $(readlink -f "$dst") == "$(readlink -f "$src")" ]]; then
        echo "  ok      $rel"; continue
    fi
    if [[ -e $dst || -L $dst ]]; then
        mkdir -p "$BACKUP/$(dirname "$rel")"
        mv "$dst" "$BACKUP/$rel"
        echo "  backup  $rel -> $BACKUP/$rel"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  linked  $rel"
done

cat <<EOF

Done. Optional system-level steps (need sudo, see README):
  sudo bash $DOT/.local/share/caelestia-github-tab/install.sh   # GitHub tab + night-light pill
  sudo bash $DOT/sddm/install.sh                                # SDDM jake login screen
Then restart the shell:  caelestia shell -d   (or log out and back in)
EOF
