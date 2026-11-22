if status is-interactive
    # Clean startup: no stray characters typed in (fish's terminal queries sometimes
    # leak their replies as input in foot) and no doubled prompt when Hyprland resizes
    # the new window into its tile. The feature flag is read at startup, so it must be
    # a universal variable; this sets it once.
    contains no-query-term $fish_features; or set -Ua fish_features no-query-term
    set -g fish_handle_reflow 1
    # If the window is resized while fish is still starting (Hyprland tiling it), the
    # first prompt was drawn at the old width and leaves a stray copy above. Until the
    # first command runs, a resize wipes the screen and redraws the prompt at the top.
    function __startup_resize --on-signal WINCH
        printf '\e[H\e[2J'
        commandline -f repaint
    end
    function __startup_resize_done --on-event fish_preexec
        functions -e __startup_resize __startup_resize_done
    end

    # Starship custom prompt
    command -v starship &> /dev/null && starship init fish | source

    # Direnv + Zoxide
    command -v direnv &> /dev/null && direnv hook fish | source
    command -v zoxide &> /dev/null && zoxide init fish --cmd cd | source

    # Better ls
    command -v eza &> /dev/null && alias ls='eza --icons --group-directories-first -1'

    # Abbrs
    abbr lg 'lazygit'
    abbr gd 'git diff'
    abbr ga 'git add .'
    abbr gc 'git commit -am'
    abbr gl 'git log'
    abbr gs 'git status'
    abbr gst 'git stash'
    abbr gsp 'git stash pop'
    abbr gp 'git push'
    abbr gpl 'git pull'
    abbr gsw 'git switch'
    abbr gsm 'git switch main'
    abbr gb 'git branch'
    abbr gbd 'git branch -d'
    abbr gco 'git checkout'
    abbr gsh 'git show'

    abbr l 'ls'
    abbr ll 'ls -l'
    abbr la 'ls -a'
    abbr lla 'ls -la'

    # Custom colours
    cat ~/.local/state/caelestia/sequences.txt 2> /dev/null

    # For jumping between prompts in foot terminal
    function mark_prompt_start --on-event fish_prompt
        echo -en "\e]133;A\e\\"
    end

    # Custom fish config
    set -q XDG_CONFIG_HOME && set -l cConf $XDG_CONFIG_HOME/caelestia || set -l cConf $HOME/.config/caelestia
    source $cConf/user-config.fish 2> /dev/null
end
