#!/usr/bin/env python3
"""Generate solid-color placeholder PNGs for the Roku manifest."""
import os, struct, zlib

def write_png(path, w, h, rgb):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    row = b"\x00" + bytes(rgb) * w
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(row * h))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)

os.makedirs("images", exist_ok=True)
teal = (16, 84, 92)
write_png("images/icon_focus_hd.png", 290, 218, teal)
write_png("images/icon_focus_sd.png", 246, 140, teal)
write_png("images/splash_fhd.png", 1920, 1080, (16, 20, 24))
write_png("images/splash_hd.png", 1280, 720, (16, 20, 24))
write_png("images/splash_sd.png", 720, 480, (16, 20, 24))
print("wrote images/")
