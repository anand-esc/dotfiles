# `gitb` + Enter + Enter -> opens GitHub in the browser.
# Any other key (or Ctrl-C) at the prompt cancels.
function gitb --description 'Open GitHub in the browser'
    read --local --prompt-str (set_color brblack)'↵ Enter to open GitHub · any key to cancel: '(set_color normal) reply
    or return 1
    if test -z "$reply"
        setsid -f xdg-open https://github.com >/dev/null 2>&1
    end
end
