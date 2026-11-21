#!/usr/bin/env python3
"""Add local Caelestia additions (dashboard GitHub tab, bar night-light pill). Idempotent.

Usage: apply.py [SHELL_DIR]   (default /etc/xdg/quickshell/caelestia)
Copies GitHubTab.qml from this script's share dir and patches Content.qml.
"""

import os
import shutil
import sys

SHARE = os.path.dirname(os.path.abspath(__file__))
SHELL = sys.argv[1] if len(sys.argv) > 1 else "/etc/xdg/quickshell/caelestia"
DASH = os.path.join(SHELL, "modules", "dashboard")
CONTENT = os.path.join(DASH, "Content.qml")
MARKER = "// caelestia-github-tab"

TAB_ANCHOR = """                enabled: Config.dashboard.showWeather
            }"""
TAB_ENTRY = """                enabled: Config.dashboard.showWeather
            },
            { // caelestia-github-tab
                component: githubComponent,
                iconName: "code",
                text: "GitHub",
                enabled: true
            }"""

COMP_ANCHOR = """                WeatherTab {}
            }"""
COMP_ENTRY = """                WeatherTab {}
            }

            Component { // caelestia-github-tab
                id: githubComponent

                GitHubTab {
                    screenState: root.screenState
                }
            }"""


def warn(msg):
    print(f"caelestia-github-tab: {msg}", file=sys.stderr)


BAR = os.path.join(SHELL, "modules", "bar", "Bar.qml")
BAR_ANCHOR = '''            DelegateChoice {
                roleValue: "clock"'''
BAR_ENTRY = '''            DelegateChoice { // caelestia-nightlight
                roleValue: "nightLight"
                delegate: EntryWrapper {
                    NightLight {}
                }
            }
            DelegateChoice {
                roleValue: "clock"'''


def apply_nightlight():
    comp_dir = os.path.join(SHELL, "modules", "bar", "components")
    if not os.path.isfile(BAR) or not os.path.isdir(comp_dir):
        warn("bar files not found, skipping night light")
        return
    shutil.copyfile(os.path.join(SHARE, "NightLight.qml"), os.path.join(comp_dir, "NightLight.qml"))
    src = open(BAR).read()
    if "caelestia-nightlight" in src:
        print("caelestia-nightlight: already applied (component refreshed)")
        return
    if src.count(BAR_ANCHOR) != 1:
        warn("Bar.qml layout changed upstream; night light NOT added. Update apply.py.")
        return
    tmp = BAR + ".nl-tmp"
    with open(tmp, "w") as f:
        f.write(src.replace(BAR_ANCHOR, BAR_ENTRY))
    shutil.copymode(BAR, tmp)
    os.replace(tmp, BAR)
    print("caelestia-nightlight: night light pill added")


def main():
    apply_nightlight()
    if not os.path.isfile(CONTENT):
        warn(f"{CONTENT} not found, skipping")
        return

    shutil.copyfile(os.path.join(SHARE, "GitHubTab.qml"), os.path.join(DASH, "GitHubTab.qml"))

    src = open(CONTENT).read()
    if MARKER in src:
        print("caelestia-github-tab: already applied (tab file refreshed)")
        return
    if src.count(TAB_ANCHOR) != 1 or src.count(COMP_ANCHOR) != 1:
        warn("Content.qml layout changed upstream; tab NOT added. Update apply.py.")
        return

    src = src.replace(TAB_ANCHOR, TAB_ENTRY).replace(COMP_ANCHOR, COMP_ENTRY)
    tmp = CONTENT + ".github-tmp"
    with open(tmp, "w") as f:
        f.write(src)
    shutil.copymode(CONTENT, tmp)
    os.replace(tmp, CONTENT)
    print("caelestia-github-tab: GitHub tab added")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never fail a pacman transaction
        warn(f"error: {e}")
