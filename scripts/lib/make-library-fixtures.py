#!/usr/bin/env python3
"""Deterministic synthetic images for the library acceptance suite."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "entry/src/ohosTest/resources/rawfile/library-enhancements"
OUT.mkdir(parents=True, exist_ok=True)
FONT_CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_LATIN = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def font(size: int, cjk: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_CJK if cjk else FONT_LATIN, size)


def text_line(draw: ImageDraw.ImageDraw, y: int, chinese: str, english: str) -> None:
    draw.text((38, y), chinese, font=font(44, True), fill=(13, 26, 42))
    draw.text((38, y + 60), english, font=font(48), fill=(13, 26, 42))


def corner_image(width: int, height: int, transparent: bool) -> Image.Image:
    image = Image.new("RGBA", (width, height), (245, 245, 245, 255))
    draw = ImageDraw.Draw(image)
    if transparent:
        draw.rectangle((width // 3, height // 3, 2 * width // 3, 2 * height // 3), fill=(0, 0, 0, 0))
    side = 48
    draw.rectangle((0, 0, side, side), fill=(255, 0, 0, 255))
    draw.rectangle((width - side, 0, width - 1, side), fill=(0, 255, 0, 255))
    draw.rectangle((0, height - side, side, height - 1), fill=(0, 0, 255, 255))
    draw.rectangle((width - side, height - side, width - 1, height - 1), fill=(255, 255, 0, 255))
    return image


def write_images() -> dict[str, dict]:
    cases: dict[str, dict] = {}

    bilingual = Image.new("RGB", (900, 480), "white")
    draw = ImageDraw.Draw(bilingual)
    text_line(draw, 80, "订单号", "EAST-2048")
    text_line(draw, 245, "发票编号", "INVOICE-7A")
    bilingual.save(OUT / "ocr-bilingual.png", optimize=False)
    cases["ocr-bilingual.png"] = {"caseId": "ocr-bilingual", "expectedPhrases": ["订单号", "EAST-2048", "发票编号", "INVOICE-7A"]}

    long = Image.new("RGB", (900, 4200), "white")
    draw = ImageDraw.Draw(long)
    text_line(draw, 100, "顶端", "TOP-ALPHA")
    text_line(draw, 1950, "中段", "MID-BRAVO")
    text_line(draw, 3910, "末尾", "END-CHARLIE")
    long.save(OUT / "ocr-long.png", optimize=False)
    cases["ocr-long.png"] = {"caseId": "ocr-long", "expectedPhrases": ["顶端", "TOP-ALPHA", "中段", "MID-BRAVO", "末尾", "END-CHARLIE"]}

    Image.new("RGB", (500, 300), "white").save(OUT / "ocr-empty.png", optimize=False)
    cases["ocr-empty.png"] = {"caseId": "ocr-empty", "expectedPhrases": []}

    similar = Image.new("RGB", (320, 240), (242, 235, 220))
    draw = ImageDraw.Draw(similar)
    draw.rectangle((34, 24, 285, 200), fill=(35, 80, 146))
    draw.ellipse((80, 44, 255, 209), fill=(235, 186, 37))
    draw.line((30, 212, 290, 20), fill=(180, 27, 55), width=13)
    similar.save(OUT / "similar-base.png", optimize=False)
    similar.resize((640, 480), Image.Resampling.LANCZOS).save(OUT / "similar-resized.jpg", quality=82, subsampling=0)
    Image.new("RGB", (320, 240), (25, 170, 92)).save(OUT / "similar-different.png", optimize=False)
    cases["similar-base.png"] = {"caseId": "similar-base", "expectedGroup": "pair-a"}
    cases["similar-resized.jpg"] = {"caseId": "similar-resized", "expectedGroup": "pair-a"}
    cases["similar-different.png"] = {"caseId": "similar-different", "expectedGroup": "none"}

    edit = corner_image(300, 400, True)
    draw = ImageDraw.Draw(edit)
    draw.ellipse((142, 192, 158, 208), fill=(0, 70, 255, 255))
    edit.save(OUT / "edit-oracle.png", optimize=False)
    cases["edit-oracle.png"] = {"caseId": "edit-oracle", "samplePixels": {
        "topLeft": [255, 0, 0, 255], "topRight": [0, 255, 0, 255],
        "bottomLeft": [0, 0, 255, 255], "bottomRight": [255, 255, 0, 255],
        "transparent": [0, 0, 0, 0], "blueDot": [0, 70, 255, 255],
    }}

    raw = corner_image(60, 40, False).convert("RGB")
    for orientation in range(1, 9):
        exif = Image.Exif()
        exif[274] = orientation
        name = f"exif-{orientation}.jpg"
        raw.save(OUT / name, quality=100, subsampling=0, exif=exif)
        cases[name] = {"caseId": f"exif-{orientation}", "orientation": orientation}

    return cases


def manifest(cases: dict[str, dict]) -> dict:
    entries = []
    for name, extras in sorted(cases.items()):
        path = OUT / name
        with Image.open(path) as image:
            entry = {"name": name, "width": image.width, "height": image.height,
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            entry.update(extras)
            entries.append(entry)
    return {"version": 1, "generator": "scripts/make-library-fixtures.cjs", "cases": entries}


def verify(data: dict) -> None:
    for entry in data["cases"]:
        path = OUT / entry["name"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], path
        with Image.open(path) as image:
            assert (image.width, image.height) == (entry["width"], entry["height"]), path
            if "orientation" in entry:
                assert image.getexif().get(274) == entry["orientation"], path
            if "samplePixels" in entry:
                width, height = image.size
                samples = {"topLeft": (10, 10), "topRight": (width - 10, 10),
                           "bottomLeft": (10, height - 10), "bottomRight": (width - 10, height - 10),
                           "transparent": (width // 2, height // 2 - 40), "blueDot": (width // 2, height // 2)}
                for key, location in samples.items():
                    assert list(image.getpixel(location)) == entry["samplePixels"][key], (path, key)


if __name__ == "__main__":
    result = manifest(write_images())
    verify(result)
    (OUT / "manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Verified {len(result['cases'])} synthetic fixtures in {OUT}")
