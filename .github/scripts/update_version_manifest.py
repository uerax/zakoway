#!/usr/bin/env python3
import glob
import hashlib
import json
import os
from datetime import datetime

def compute_sha256(filepath: str) -> str:
    hasher = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest().lower()

def main():
    tag = os.environ.get('GITHUB_REF_NAME', '').strip()
    if not tag:
        tag = 'latest'
    clean_version = tag[1:] if tag.startswith('v') else tag

    repo = os.environ.get('GITHUB_REPOSITORY', 'uerax/zakoway').strip()
    run_number = os.environ.get('GITHUB_RUN_NUMBER', '1').strip()
    try:
        build_number = int(run_number)
    except ValueError:
        build_number = 1

    today = datetime.now().strftime('%Y-%m-%d')
    is_pre = any(sub in tag.lower() for sub in ['beta', 'alpha', 'rc', 'pre'])

    patterns = {
        'windows_x64': 'release-assets/Zakoway-*-windows-x64.zip',
        'android_arm64': 'release-assets/Zakoway-*-android-arm64-v8a.apk',
        'android_universal': 'release-assets/Zakoway-*-android-universal.apk',
        'macos_universal': 'release-assets/Zakoway-*-macos-universal.zip',
        'ios': 'release-assets/Zakoway-*-ios.ipa',
    }

    assets = {}
    for key, pattern in patterns.items():
        matches = glob.glob(pattern)
        if matches:
            filepath = matches[0]
            filename = os.path.basename(filepath)
            size = os.path.getsize(filepath)
            sha256_hash = compute_sha256(filepath)
            assets[key] = {
                'fileName': filename,
                'url': f'https://github.com/{repo}/releases/download/{tag}/{filename}',
                'size': size,
                'sha256': sha256_hash,
            }
            print(f"[OK] {key}: {filename} (Size: {size} bytes, SHA-256: {sha256_hash})")
        else:
            print(f"[WARN] No file found matching pattern: {pattern}")

    manifest_path = 'version.json'
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, 'r', encoding='utf-8') as f:
                manifest = json.load(f)
        except Exception as e:
            print(f"[WARN] Failed to load existing {manifest_path}: {e}")

    if not isinstance(manifest, dict):
        manifest = {}

    target_channel = 'beta' if is_pre else 'latest'
    existing_node = manifest.get(target_channel, {}) if isinstance(manifest.get(target_channel), dict) else {}
    min_supported = manifest.get('latest', {}).get('minSupportedVersion', '0.0.1')

    title = f"{tag} {'测试尝鲜版' if is_pre else '正式稳定版'}发布"
    changelog = existing_node.get('changelog', '')
    if not changelog:
        changelog = f"1. {title}\n2. 稳定性增强与已知问题修复"

    new_node = {
        'version': clean_version,
        'buildNumber': build_number,
        'releaseDate': today,
        'minSupportedVersion': min_supported,
        'isPrerelease': is_pre,
        'title': title,
        'changelog': changelog,
        'downloads': assets,
    }

    if is_pre:
        manifest['beta'] = new_node
        if 'latest' not in manifest:
            manifest['latest'] = new_node
    else:
        manifest['latest'] = new_node
        manifest['beta'] = new_node

    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"[SUCCESS] Updated {manifest_path} for {tag} (channel={target_channel}, is_pre={is_pre})")

if __name__ == '__main__':
    main()
