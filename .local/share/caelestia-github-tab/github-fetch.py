#!/usr/bin/env python3
"""Fetch GitHub profile, repos, contributions and notifications via `gh`
and cache them for the Caelestia dashboard GitHub tab.

Output: $XDG_CACHE_HOME/caelestia/github.json (+ github-avatar.png)
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "caelestia")
OUT = os.path.join(CACHE, "github.json")
AVATAR = os.path.join(CACHE, "github-avatar.png")

QUERY = """
query {
  viewer {
    login name bio url avatarUrl(size: 200)
    followers { totalCount }
    following { totalCount }
    repositories(ownerAffiliations: OWNER, first: 8, orderBy: {field: PUSHED_AT, direction: DESC}) {
      totalCount
      nodes {
        name description url isPrivate isFork stargazerCount forkCount pushedAt
        primaryLanguage { name color }
      }
    }
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks { contributionDays { date contributionCount contributionLevel } }
      }
    }
  }
}
"""

LEVELS = {"NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4}


def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or f"gh exited with {r.returncode}")
    return json.loads(r.stdout)


def html_url(api_url, repo_url):
    """Turn a notification subject API URL into a browser URL."""
    if not api_url:
        return repo_url
    url = api_url.replace("https://api.github.com/repos/", "https://github.com/")
    url = url.replace("/pulls/", "/pull/").replace("/commits/", "/commit/")
    return url


def write(data):
    os.makedirs(CACHE, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CACHE, prefix=".github-", suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp, OUT)


def previous():
    try:
        with open(OUT) as f:
            return json.load(f)
    except Exception:
        return {}


def main():
    auth = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if auth.returncode != 0:
        data = previous()
        data.update(ok=False, error="notLoggedIn", fetchedAt=int(time.time()))
        write(data)
        return

    try:
        v = gh("api", "graphql", "-f", f"query={QUERY}")["data"]["viewer"]
    except Exception as e:
        data = previous()
        data.update(ok=False, error=str(e)[:200], fetchedAt=int(time.time()))
        write(data)
        return

    try:
        raw = gh("api", "notifications?per_page=15")
    except Exception:
        raw = []  # token may lack the notifications scope

    try:
        with urllib.request.urlopen(v["avatarUrl"], timeout=15) as r:
            img = r.read()
        with open(AVATAR + ".tmp", "wb") as f:
            f.write(img)
        os.replace(AVATAR + ".tmp", AVATAR)
    except Exception:
        pass

    cal = v["contributionsCollection"]["contributionCalendar"]
    data = {
        "ok": True,
        "error": "",
        "fetchedAt": int(time.time()),
        "user": {
            "login": v["login"],
            "name": v["name"] or v["login"],
            "bio": v["bio"] or "",
            "url": v["url"],
            "followers": v["followers"]["totalCount"],
            "following": v["following"]["totalCount"],
            "repoCount": v["repositories"]["totalCount"],
        },
        "repos": [
            {
                "name": r["name"],
                "description": r["description"] or "",
                "url": r["url"],
                "private": r["isPrivate"],
                "fork": r["isFork"],
                "stars": r["stargazerCount"],
                "forks": r["forkCount"],
                "pushedAt": r["pushedAt"],
                "language": (r["primaryLanguage"] or {}).get("name", ""),
                "languageColor": (r["primaryLanguage"] or {}).get("color") or "",
            }
            for r in v["repositories"]["nodes"]
        ],
        "calendar": {
            "total": cal["totalContributions"],
            "weeks": [
                [{"date": d["date"], "count": d["contributionCount"], "level": LEVELS.get(d["contributionLevel"], 0)}
                 for d in w["contributionDays"]]
                for w in cal["weeks"]
            ],
        },
        "notifications": [
            {
                "title": n["subject"]["title"],
                "type": n["subject"]["type"],
                "repo": n["repository"]["full_name"],
                "reason": n["reason"],
                "unread": n["unread"],
                "updatedAt": n["updated_at"],
                "url": html_url(n["subject"].get("url"), n["repository"]["html_url"]),
            }
            for n in raw
        ],
    }
    write(data)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        d = previous()
        d.update(ok=False, error=str(e)[:200], fetchedAt=int(time.time()))
        write(d)
        sys.exit(1)
