"""Extract an Xbox 360 disc image (XDVDFS) to a folder.

Usage: python tools/extract_xiso.py <image.iso> <out_dir>
"""
import os
import struct
import sys

SECTOR = 2048
MAGIC = b"MICROSOFT*XBOX*MEDIA"
# Game partition offsets: plain XISO, XGD2, XGD3, XGD1
PARTITIONS = (0, 0xFD90000, 0x2080000, 0x18300000)


def find_partition(f):
    for base in PARTITIONS:
        f.seek(base + 32 * SECTOR)
        if f.read(len(MAGIC)) == MAGIC:
            return base
    sys.exit("Not an Xbox disc image (no XDVDFS header found)")


def walk(f, base, dir_sector, dir_size, out):
    f.seek(base + dir_sector * SECTOR)
    table = f.read(dir_size)
    stack = [0]
    while stack:
        pos = stack.pop()
        if pos + 14 > len(table):
            continue
        left, right, sector, size, attr, nlen = struct.unpack_from("<HHIIBB", table, pos)
        if left == 0xFFFF:  # padding, not an entry
            continue
        # Names are plain ASCII on retail discs; reject path tricks.
        name = table[pos + 14 : pos + 14 + nlen].decode("latin-1")
        if not name or name in (".", "..") or "/" in name or "\\" in name:
            sys.exit(f"Refusing suspicious entry name: {name!r}")
        path = os.path.join(out, name)
        if attr & 0x10:  # directory
            os.makedirs(path, exist_ok=True)
            if size:
                walk(f, base, sector, size, path)
        else:
            copy(f, base + sector * SECTOR, size, path)
        if left:
            stack.append(left * 4)
        if right:
            stack.append(right * 4)


def copy(f, offset, size, path):
    f.seek(offset)
    with open(path, "wb") as o:
        while size:
            chunk = f.read(min(size, 1 << 20))
            if not chunk:
                sys.exit(f"Image truncated while reading {path}")
            o.write(chunk)
            size -= len(chunk)
    print(path)


def main():
    iso, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    with open(iso, "rb") as f:
        base = find_partition(f)
        f.seek(base + 32 * SECTOR + len(MAGIC))
        root_sector, root_size = struct.unpack("<II", f.read(8))
        walk(f, base, root_sector, root_size, out)
    xex = os.path.join(out, "default.xex")
    with open(xex, "rb") as x:
        assert x.read(4) == b"XEX2", "default.xex missing or not an XEX2 file"
    print("OK: default.xex is a valid XEX2")


if __name__ == "__main__":
    main()
