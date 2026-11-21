#!/usr/bin/env python3
"""Tạo dist/update.json mô tả bản phát hành (phiên bản, build, kênh, SHA-256 của .deb và .ipa).

Đọc các biến môi trường: VERSION, BUILD_NUMBER, CHANNEL (stable|dev), COMMIT, REPO (chủ/tên), TAG.
App kiểm tra tệp này (và chữ ký update.json.sig nếu có) trước khi cho tải bản mới.
"""
import datetime
import glob
import hashlib
import json
import os
import subprocess
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    version = os.environ["VERSION"]
    build = int(os.environ["BUILD_NUMBER"])
    channel = os.environ["CHANNEL"]
    commit = os.environ["COMMIT"][:7]
    repo = os.environ["REPO"]
    tag = os.environ["TAG"]

    if channel == "stable" and os.path.exists("RELEASE_NOTES.md"):
        notes = open("RELEASE_NOTES.md", encoding="utf-8").read().strip()
    else:
        notes = subprocess.run(["git", "log", "-1", "--format=%B"], capture_output=True, text=True).stdout.strip()
    notes = notes[:1500]

    files = {}
    for kind, pattern in (("deb", "dist/*.deb"), ("ipa", "dist/*.ipa")):
        matches = sorted(glob.glob(pattern))
        if len(matches) != 1:
            sys.exit("expected exactly one file for %s, found %s" % (pattern, matches))
        path = matches[0]
        name = os.path.basename(path)
        files[kind] = {
            "name": name,
            "url": "https://github.com/%s/releases/download/%s/%s" % (repo, tag, name),
            "sha256": sha256(path),
            "size": os.path.getsize(path),
        }

    manifest = {
        "app": "com.puc.mochyios",
        "version": version,
        "build": build,
        "channel": channel,
        "commit": commit,
        "minOS": "12.2",
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "notes": notes,
        "files": files,
    }
    with open("dist/update.json", "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps(manifest, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
