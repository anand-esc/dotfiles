# YouTube in the terminal (`yt`)

Search YouTube, pick a result with a thumbnail preview, and play it in mpv. No browser needed.

## Commands

| Command | What it does |
|---|---|
| `yt` | Ask for a search, then show results |
| `yt lofi hip hop` | Search directly |
| `yt -a lofi hip hop` | Audio-only mode: Enter plays sound in the terminal |
| `yt https://youtu.be/...` | Play a link directly |
| `yt -a https://youtu.be/...` | Play a link as audio only |
| `yt --help` | Show the built-in help |

## Keys in the results list

| Key | Action |
|---|---|
| `Enter` | Play the video in an mpv window (the list stays open) |
| `Alt-a` | Play audio only in the terminal (`q` returns to the list) |
| `Alt-d` | Download to `~/Videos/YouTube` |
| `Ctrl-y` | Copy the video link |
| `Ctrl-s` | New search |
| `Esc` | Quit |
| Type | Filter the results |

## mpv controls (while playing)

| Key | Action |
|---|---|
| `Space` | Pause / resume |
| `←` / `→` | Seek 5 s back / forward |
| `↑` / `↓` | Seek 1 min forward / back |
| `9` / `0` | Volume down / up |
| `m` | Mute |
| `f` | Fullscreen |
| `v` | Toggle subtitles |
| `[` / `]` | Slower / faster playback |
| `s` | Screenshot |
| `q` | Quit (remembers where you stopped) |
| `Shift-q` | Quit without saving the position |

## Settings

- **Results per search:** `YT_RESULTS=50 yt <search>` (default 25)
- **Download folder:** `YT_DOWNLOAD_DIR=~/Downloads yt <search>`
- **Quality:** up to 1440p60, set in `~/.config/mpv/mpv.conf` (`ytdl-format=`)

## Files

- `~/.local/bin/yt`: the script
- `~/.config/mpv/mpv.conf`: mpv settings (hardware decoding, quality, resume)
- `~/.cache/yt-thumbs/`: cached thumbnails (safe to delete)

## Troubleshooting

- **Videos take ~15–20 s to start:** that's normal. yt-dlp has to pass YouTube's anti-bot check first.
- **No results or videos won't play:** update yt-dlp with `yay -Syu`. YouTube changes often, and yt-dlp updates keep up.
- **No thumbnails:** they need the `foot` terminal (sixel images) and `chafa`.
