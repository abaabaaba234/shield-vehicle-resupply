#!/usr/bin/env python3
"""把 Lua 源码打包成 Bingus 可发现的 9ba626afa44a3aa3.patch_0 + mod 管理器 zip。
用法: python pack_patch.py <输出zip> <mod名称> <lua文件> [<lua文件> ...]
每个 lua 文件第一行必须是 "-- HD2-Addon: mods/<a>/<b>"，资源名 hash = murmur64("mods/<a>/<b>")。
格式照抄 Bingus Shared Loader v17 自己的 patch_0（1 个类型、每个文件一条 80 字节记录）。"""
import struct, sys, zipfile, json, uuid, hashlib
from pathlib import Path

M = 0xFFFFFFFFFFFFFFFF
def murmur64(key, seed=0):
    m, r, n = 0xc6a4a7935bd1e995, 47, len(key)
    h = (seed ^ (n * m)) & M
    i = 0
    while n - i >= 8:
        k = (int.from_bytes(key[i:i+8], 'little') * m) & M
        k ^= k >> r; k = (k * m) & M
        h ^= k; h = (h * m) & M; i += 8
    if key[i:]:
        h ^= int.from_bytes(key[i:], 'little'); h = (h * m) & M
    h ^= h >> r; h = (h * m) & M; h ^= h >> r
    return h
assert murmur64(b'mods/codex/exo_launcher') == 0xccdfad2ab9f2ff47  # 与 EXO mod 的 patch 对照过

LUA_TYPE = 0xa14e8dfa2cd117e2

def build_patch(sources):
    files = []
    for src in sources:
        first = src.split(b'\n', 1)[0].strip()
        assert first.startswith(b'-- HD2-Addon: mods/'), 'first line must be -- HD2-Addon: mods/<a>/<b>'
        path = first[len(b'-- HD2-Addon: '):]
        files.append((murmur64(path), path.decode(), struct.pack('<II', len(src), 2) + src))
    n = len(files)
    header_len = 72 + 32 + 80 * n
    off = (header_len + 15) & ~15
    entries, body = b'', b''
    for idx, (h, _, blob) in enumerate(files):
        pos = off + len(body)
        entries += struct.pack('<QQQQQQQIIIIII', h, LUA_TYPE, pos, 0, 0, 0, 0, len(blob), 0, 0, 0x10, 0x10, idx)
        body += blob + b'\0' * ((-len(blob)) % 16)
    total = off + len(body)
    head = struct.pack('<IIII', 0xF0000011, 1, n, 0) + b'\0' * 16 + struct.pack('<Q', total) + b'\0' * 32
    tentry = struct.pack('<IIQQII', 0, 0, LUA_TYPE, n, 0x10, 0x10)
    data = head + tentry + entries
    data += b'\0' * (off - len(data)) + body
    assert len(data) == total
    return data, files

def main():
    out, name, *luas = sys.argv[1:]
    sources = [open(p, 'rb').read().replace(b'\r\n', b'\n') for p in luas]
    patch, files = build_patch(sources)
    manifest = {
        "Version": 1, "Guid": str(uuid.uuid5(uuid.NAMESPACE_URL, 'hd2-shieldresupply-' + name)),
        "Name": name, "Description": "Based on v0.25. Requires Bingus Shared Loader v17+. Optional bilingual settings: ModOptionsMenu API 1/version 2. Addons: " + ', '.join(f[1] for f in files),
        "Options": [{"Name": name, "Description": "Enable " + name, "Include": ["data"]}],
    }
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('manifest.json', json.dumps(manifest, indent=2, ensure_ascii=False))
        z.writestr('data/9ba626afa44a3aa3.patch_0', patch)
        z.writestr('data/9ba626afa44a3aa3.patch_0.stream', b'')
        z.writestr('data/9ba626afa44a3aa3.patch_0.gpu_resources', b'')
        z.writestr('INSTALL_菜单说明.md', (Path(__file__).resolve().parents[1]/'docs/MODS菜单.md').read_bytes())
    for h, p, blob in files: print(f'{h:016x}  {p}  ({len(blob)} bytes)')
    print('patch', len(patch), 'bytes, sha256', hashlib.sha256(patch).hexdigest().upper(), '->', out)

if __name__ == '__main__':
    main()
