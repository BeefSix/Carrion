#!/usr/bin/env python3
"""
Pixellab animation downloader. Reads the textual output of the MCP
get_character tool from stdin, extracts animation frame URLs, and writes
them to disk at <root>/<action>/<dir>/<frame>.png.

Usage:
  python pixellab_dl.py <root_dir> <anim_to_action_map>
    root_dir            e.g. assets/sprites/units/military/heavy_gunner
    anim_to_action_map  comma-separated, e.g.
                        breathing-idle=idle,walking-8-frames=walk,attack=attack,falling-back-death=death

Pipe `get_character` output into stdin.

The MCP output uses lines like:
  breathing-idle (south-west, 4f) 2026-06-09
    frames: <url1>, <url2>, <url3>, <url4>

We pair the "anim (dir, Nf)" header with the next "frames:" line and
emit frame downloads.
"""

import re
import sys
import os
from concurrent.futures import ThreadPoolExecutor

# Lazy import; only needed when run.
try:
    import urllib.request
except ImportError:
    urllib = None


HEADER_RE = re.compile(r'^\s{2}([\w-]+)\s+\(([^,]+),\s*\d+f\)\s', re.MULTILINE)
URL_RE = re.compile(r'https://\S+\.png')


def parse(input_text):
    """Yield (anim_name, direction, [url, ...])."""
    lines = input_text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^\s{2}([\w-]+)\s+\(([^,]+),\s*(\d+)f\)', line)
        if m:
            anim_name = m.group(1)
            direction = m.group(2).strip()
            # Next non-blank line should be 'frames: u1, u2, ...'
            for j in range(i + 1, min(i + 4, len(lines))):
                if 'frames:' in lines[j]:
                    urls = URL_RE.findall(lines[j])
                    if urls:
                        yield anim_name, direction, urls
                    i = j
                    break
        i += 1


def download_one(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    urllib.request.urlretrieve(url, path)
    return path


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    root = sys.argv[1].rstrip('/').rstrip('\\')
    anim_map = {}
    for pair in sys.argv[2].split(','):
        k, v = pair.split('=')
        anim_map[k.strip()] = v.strip()

    text = sys.stdin.read()
    jobs = []
    for anim, direction, urls in parse(text):
        if anim not in anim_map:
            continue
        action = anim_map[anim]
        for idx, url in enumerate(urls):
            path = os.path.join(root, action, direction, f'{idx}.png')
            jobs.append((url, path))

    print(f'[pixellab_dl] {len(jobs)} files to fetch into {root}')
    fail = 0
    with ThreadPoolExecutor(max_workers=8) as ex:
        for fut in [ex.submit(download_one, u, p) for u, p in jobs]:
            try:
                fut.result()
            except Exception as e:
                fail += 1
                print(f'[pixellab_dl] FAIL: {e}')
    print(f'[pixellab_dl] done: {len(jobs) - fail} ok, {fail} failed')


if __name__ == '__main__':
    main()
