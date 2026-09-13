#!/usr/bin/env python3
"""Load a mesh, render with the cmodel golden lib, display the framebuffer in Tk."""
import ctypes
import sys
import os

LIB_PATH = os.path.join(os.path.dirname(__file__), "c_model", "build", "libcmodel_golden.so")
MESH = os.path.join(os.path.dirname(__file__), "tests", "testcases", "memh", "utah.memh")
W, H = 320, 240


def render():
    lib = ctypes.CDLL(LIB_PATH)
    lib.cmodel_init.restype = ctypes.c_uint
    lib.cmodel_load_mesh.restype = ctypes.c_uint
    lib.cmodel_render.restype = ctypes.c_uint
    lib.cmodel_fb_pixel.restype = ctypes.c_uint
    lib.cmodel_fb_pixel.argtypes = [ctypes.c_int, ctypes.c_int]

    rc = lib.cmodel_init(W, H)
    print(f"cmodel_init: rc={rc}")
    rc = lib.cmodel_load_mesh(MESH.encode())
    print(f"cmodel_load_mesh: rc={rc}")
    rc = lib.cmodel_render()
    print(f"cmodel_render: rc={rc}")

    pixels = []
    for y in range(H):
        for x in range(W):
            pixels.append(lib.cmodel_fb_pixel(x, y))
    return pixels


def main():
    pixels = render()

    if "--save" in sys.argv:
        path = sys.argv[sys.argv.index("--save") + 1]
        from PIL import Image
        buf = bytearray(H * W)
        for i, p in enumerate(pixels):
            # RGB565 grey word {L, {L, L[4]}, L}: the 5-bit intensity L sits in
            # bits [4:0] (Blue) and [15:11] (Red); & 0x1F recovers L.
            buf[i] = (p & 0x1F) * 255 // 31
        img = Image.frombytes("L", (W, H), bytes(buf))
        img.save(path)
        print(f"saved {W}x{H} -> {path}")
        return

    if "--no-gui" in sys.argv:
        nz = sum(1 for p in pixels if p)
        print(f"non-zero pixels: {nz}/{len(pixels)}")
        return

    import tkinter as tk
    img = tk.PhotoImage(width=W, height=H)
    for y in range(H):
        row = []
        for x in range(W):
            w = pixels[y * W + x]
            cc = w & 0x1F  # RGB565 grey: Blue [4:0] holds the 5-bit intensity L
            g = (cc * 255) // 31
            row.append(f"#{g:02x}{g:02x}{g:02x}")
        img.put(row, to=(0, y))

    win = tk.Tk()
    win.title("cmodel golden framebuffer (320x240)")
    tk.Label(win, image=img).pack()
    win.mainloop()


if __name__ == "__main__":
    main()
