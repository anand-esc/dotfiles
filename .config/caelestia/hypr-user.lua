hl.config({
    input = {
        sensitivity = 0.5,
    },
})

-- Laptop panel: 2880x1800, scaled 1.25x -> 2304x1440 workspace
-- 90 Hz, or 60 Hz in the Power Saver profile (power-mode-watch switches it live)
local function power_saver()
    local f = io.open("/var/lib/power-profiles-daemon/state.ini", "r")
    if not f then return false end
    local s = f:read("*a")
    f:close()
    return s:match("Profile=power%-saver") ~= nil
end

hl.monitor({
    output   = "eDP-1",
    mode     = power_saver() and "2880x1800@60" or "2880x1800@90",
    position = "auto",
    scale    = 1.25,
})

-- Auto power profile on plug/unplug (performance on AC, balanced on battery)
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/power-mode-watch")
end)

-- Variable refresh rate, fullscreen apps only (video/games): smoother + saves power
hl.config({
    misc = {
        vrr = 2,
    },
})

-- Power button: lock the screen instead of shutting down (only while logged in).
-- Holding the button 4+ s still force-powers-off (hardware); at the login screen it shuts down normally.
hl.bind("XF86PowerOff", hl.dsp.global("caelestia:lock"))
hl.on("hyprland.start", function()
    hl.exec_cmd("systemd-inhibit --what=handle-power-key --who=Hyprland --why='Power button locks the screen' --mode=block sleep infinity")
end)

-- wallfx: wallpaper transitions (outline / pixel colonies) + skewed-card picker
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c wallfx -n -d")
end)
hl.bind("SUPER + SHIFT + W", hl.dsp.global("wallfx:picker"))
