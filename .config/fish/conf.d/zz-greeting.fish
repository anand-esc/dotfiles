# Greeting: your name in big letters, spaced to sit evenly on top of blackfetch.
# The name is $USER in capitals; change it with:  set -U fish_banner_name "ANY NAME"
function fish_greeting
    set -g __greeting_busy 1
    __greeting_draw
    set -e __greeting_busy
    # the window was resized while drawing (Hyprland tiling it): draw once more, clean
    if set -q __greeting_redo
        set -e __greeting_redo
        printf '\e[H\e[2J\e[3J'
        __greeting_draw
    end
    set -g __greeted 1
end

function __greeting_draw
    set -l out (fastfetch -c blackarch --pipe false 2>/dev/null)
    or return
    # width of the fetch block, and how far its leftmost character is indented
    set -l w 0
    set -l lead 999
    for l in $out
        set -l v (string length --visible -- $l)
        test $v -gt $w; and set w $v
        set -l plain (string replace -ra '\e\[[0-9;]*m' '' -- $l)
        string match -qr '\S' -- $plain; or continue
        set -l s (string length -- (string match -r '^ *' -- $plain))
        test $s -lt $lead; and set lead $s
    end
    test $lead -eq 999; and set lead 0
    test $w -gt $COLUMNS; and set w $COLUMNS
    set -l name (string upper -- $USER)
    set -q fish_banner_name; and set name $fish_banner_name
    set -l pad (string repeat -n $lead ' ')
    if command -q namebanner
        namebanner "$name" (math $w - $lead) | string replace -r '^' "$pad"
        echo
    end
    printf '%s\n' $out
end
