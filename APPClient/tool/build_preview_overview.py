"""Assemble the four locale/theme groups of actual Android device captures."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1] / "test_artifacts" / "android"
LABELS = [
    "Login", "Customer home", "New request", "Review progress",
    "Task hall", "Task detail", "Project", "Delivery", "Acceptance",
]
FONT_PATH = Path("C:/Windows/Fonts/YuGothB.ttc")


def load_font(size):
    return (
        ImageFont.truetype(str(FONT_PATH), size)
        if FONT_PATH.exists()
        else ImageFont.load_default(size=size)
    )


def build_overview(language, theme):
    prefix = f"{language}-{theme}"
    shots = sorted(ROOT.glob(f"{prefix}-[0-9][0-9]-*.png"))
    screen_numbers = [path.name.split("-")[2] for path in shots]
    expected = [f"{number:02}" for number in range(1, 10)]
    if screen_numbers != expected:
        raise SystemExit(
            f"Expected one capture for each {prefix} screen 01-09, "
            f"found {screen_numbers}"
        )

    tiles = []
    for path in shots:
        with Image.open(path) as source:
            image = source.convert("RGB")
        image = image.resize(
            (320, round(image.height * 320 / image.width)),
            Image.Resampling.LANCZOS,
        )
        tiles.append(image)

    tile_height = max(image.height for image in tiles)
    background, ink = (
        ("#E8EFEB", "#142D36") if theme == "light"
        else ("#0B1415", "#EAF4F1")
    )
    canvas = Image.new("RGB", (1056, 130 + 3 * (tile_height + 55)), background)
    draw = ImageDraw.Draw(canvas)
    font, small = load_font(22), load_font(14)
    language_label = "JAPANESE" if language == "ja" else "SIMPLIFIED CHINESE"
    draw.text(
        (24, 20), f"OPC / FLUTTER / {language_label} / {theme.upper()}",
        font=font, fill=ink,
    )
    draw.text((24, 57), "Android emulator captures", font=small, fill=ink)
    for index, image in enumerate(tiles):
        x = 24 + (index % 3) * 344
        y = 105 + (index // 3) * (tile_height + 55)
        draw.text((x, y), f"{index + 1:02}  {LABELS[index]}", font=small, fill=ink)
        canvas.paste(image, (x, y + 28))

    destination = ROOT / f"{prefix}-overview.png"
    canvas.save(destination)
    print(destination)


def main():
    for language in ("ja", "zh"):
        for theme in ("light", "dark"):
            build_overview(language, theme)


if __name__ == "__main__":
    main()
