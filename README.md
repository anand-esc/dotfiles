# dotfiles

My Arch Linux + Hyprland setup, built on the [Caelestia](https://github.com/caelestia-dots/shell) shell.
Monochrome theme, translucent bars, a local GitHub dashboard, and a few quality-of-life scripts.

## What's inside

| Path | What it is |
|---|---|
| `.config/hypr` | Hyprland config (Lua), from Caelestia's dots |
| `.config/caelestia` | Caelestia shell settings (`shell.json`), CLI settings, and **`hypr-user.lua`**: my Hyprland overrides (display scale, VRR, power button → lock, power automation) |
| `.config/foot` | Terminal: black/white palette, real ANSI colours, blue selection |
| `.config/fish` | Shell config; `gitb` + Enter + Enter opens GitHub |
| `.config/fastfetch` | Arch logo |
| `.config/mpv` | Hardware decoding (VA-API), YouTube up to 1440p, resume playback |
| `.config/btop` | btop config |
| `.config/starship.toml` | Starship prompt (single line, git/container info only when present) |
| `.local/bin/yt` | YouTube in the terminal: search, thumbnails (sixel), play/audio/download. See [`docs/ytcommands.md`](docs/ytcommands.md) |
| `.local/bin/power-mode-watch` | Charger → power profile (performance/balanced); Power Saver → 60 Hz |
| `.local/share/caelestia-github-tab` | Caelestia add-ons: **GitHub dashboard tab** (profile, contributions, repos, notifications) and **night-light bar pill** (hyprsunset). Re-applied automatically after Caelestia updates by a pacman hook |
| `surfetch/` | **surfetch**: my own fetch tool in Go (~3× faster than fastfetch). Random original anime ASCII art, info block matched to the art's height, add your own art from text or images (`surfetch --add pic.png`), pick one with `surfetch --change`. `surfetch NAME` shows a random art from your own private collection folder `~/.local/share/surfetch/arts/NAME/` (add with `--add pic.png --to NAME`). Built by `install.sh` |
| `.config/quickshell/wallfx`, `.local/bin/wallfx`, `.local/bin/wallset` | **Wallpaper transitions + picker**, adapted from [pocket-dots](https://github.com/diegoMalagrida/pocket-dots) by diegoMalagrida (**GPL-3.0**, see the folder's LICENSE). A wallpaper with a character: a thin line draws its outline, then the world grows out of it; without one: pixel colonies eat the old one. Characters are cut out once with BiRefNet (rembg; Intel GPU via OpenVINO, needs `intel-compute-runtime`, else CPU), double-checked with a person model so roads and landscapes get colonies, and cached. Picker: **Super+Shift+W** (skewed coverflow, opens on the current wallpaper, badges show each one's effect). A systemd path unit prepares new files dropped in `~/Pictures/Wallpapers`; the Caelestia patcher routes the launcher's wallpaper switcher through it too. Force a choice in `~/.config/wallfx/outline` or `no-outline`. Setup: `wallfx install`, `systemctl --user enable --now wallfx-watch.path` |
| `sddm/` | SDDM login screen: **`qylock-sword.sh`** installs the Sword theme from [qylock](https://github.com/Darkkal44/qylock) by Darkkal44 (GPL-3.0, downloaded at a pinned commit). `install.sh` switches back to [sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme) `jake_the_dog` (video AI-upscaled to 2880×1800 with Real-ESRGAN) |
| `system/` | One-off system scripts from setting up this laptop (hardware tuning, EndeavourOS → Arch branding, GRUB rename, locale fix). **Machine-specific; read before running** |
| `packages/` | `pacman.txt` (official repos) and `aur.txt` |

## Install on a new machine

```fish
git clone https://github.com/anand-esc/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh --packages   # or ./install.sh to only link configs
```

`install.sh` symlinks each config into place and moves anything already there to `~/.dotfiles-backup/<timestamp>/`.
Because the configs are symlinks, edits you make are already in the repo. Just commit and push.

Optional (sudo):

```fish
sudo bash ~/dotfiles/.local/share/caelestia-github-tab/install.sh   # GitHub tab, night light, wallfx in launcher
sudo bash ~/dotfiles/sddm/qylock-sword.sh                           # login screen (next boot)
```

Extras:
- GitHub tab: `gh auth login` once.
- Night light: `sudo pacman -S hyprsunset`.
- Local LLM: `ollama` + `ollama-vulkan`; set `OLLAMA_VULKAN=1` and `OLLAMA_IGPU_ENABLE=1` for Intel iGPUs.

## Machine-specific bits

Built on an Acer Swift Go 14 (i5-13500H, Iris Xe, 2880×1800 OLED). On other hardware, check:
- `.config/caelestia/hypr-user.lua`: monitor name `eDP-1`, mode, `scale = 1.25`
- `.local/bin/power-mode-watch`: charger path `ACAD`, monitor and mode
- `sddm/install.sh`: `SDDM_SCALE`, `SDDM_LAYOUT_W`, `SDDM_LAYOUT_H` (layout = resolution / scale)

## Keeping it updated

```fish
cd ~/dotfiles
git add -A; and git commit -m "update"; and git push
```

## Credits

[Caelestia](https://github.com/caelestia-dots) · [pocket-dots](https://github.com/diegoMalagrida/pocket-dots) (GPL-3.0) · [qylock](https://github.com/Darkkal44/qylock) (GPL-3.0) · [sddm-astronaut-theme](https://github.com/Keyitdev/sddm-astronaut-theme) (GPL-3.0) · [Hyprland](https://hyprland.org)
