#!/usr/bin/env python3
import os
import cairosvg
from pathlib import Path

# Icon sizes for app
app_sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

# Extension icons
ext_sizes = [
    (48, "icon-48.png"),
    (96, "icon-96.png"),
    (128, "icon-128.png"),
]

svg_path = Path("icon.svg")
app_icon_dir = Path("YTDownloader/Resources/Assets.xcassets/AppIcon.appiconset")
ext_icon_dir = Path("YTDownloader/YTDownloaderExtension/Resources")

print("Generating app icons...")
for size, filename in app_sizes:
    output_path = app_icon_dir / filename
    cairosvg.svg2png(url=str(svg_path), write_to=str(output_path), output_width=size, output_height=size)
    print(f"  {filename} ({size}x{size})")

print("\nGenerating extension icons...")
ext_icon_dir.mkdir(parents=True, exist_ok=True)
for size, filename in ext_sizes:
    output_path = ext_icon_dir / filename
    cairosvg.svg2png(url=str(svg_path), write_to=str(output_path), output_width=size, output_height=size)
    print(f"  {filename} ({size}x{size})")

print("\nIcons generated successfully!")
