#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError as exc:
    raise SystemExit("error: Pillow is required to generate App Store screenshots") from exc


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "store-assets" / "app-store"
FIXTURE_DIR = OUTPUT_DIR / "fixtures"
BUILD_DIR = ROOT / ".build" / "app-store-screenshots"
RENDER_DIR = BUILD_DIR / "renders"
WIDTH = 2880
HEIGHT = 1800

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_MONO = "/System/Library/Fonts/SFNSMono.ttf"

SCENES = [
    {
        "id": "folder-workspace",
        "fixture": "folder-workspace.md",
        "theme": "quartz",
        "output": "01-folder-workspace.png",
        "title": "Folder workspace",
        "subtitle": "Local Markdown files, outline-aware reading, no account.",
    },
    {
        "id": "command-palette",
        "fixture": "command-palette.md",
        "theme": "quartz",
        "output": "02-command-palette.png",
        "title": "Command palette",
        "subtitle": "Open export, search, and theme commands from the keyboard.",
    },
    {
        "id": "search-outline",
        "fixture": "search-outline.md",
        "theme": "quartz",
        "output": "03-search-outline.png",
        "title": "Search and outline",
        "subtitle": "Move through folders and long documents without leaving the file.",
    },
    {
        "id": "themed-export-readability",
        "fixture": "themed-export-readability.md",
        "theme": "graphite",
        "output": "04-themed-export-readability.png",
        "title": "Themes and export",
        "subtitle": "Readable Markdown with PDF and self-contained HTML export.",
    },
]


def font(size, mono=False):
    path = FONT_MONO if mono else FONT_REGULAR
    return ImageFont.truetype(path, size)


FONTS = {
    "toolbar": font(25),
    "sidebar_title": font(28),
    "sidebar": font(25),
    "sidebar_small": font(21),
    "mono": font(23, mono=True),
    "palette_title": font(32),
    "palette": font(26),
}


def main():
    exe = Path(os.environ.get("OURO_MD_EXE", ROOT / ".build" / "debug" / "ouro-md"))
    if not exe.exists() or not os.access(exe, os.X_OK):
        raise SystemExit(f"error: ouro-md executable not found or not executable: {exe}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)

    for scene in SCENES:
        fixture = FIXTURE_DIR / scene["fixture"]
        if not fixture.exists():
            raise SystemExit(f"error: missing fixture: {fixture}")
        render = RENDER_DIR / f"{scene['id']}-render.png"
        run_render(exe, fixture, scene["theme"], render)
        output = OUTPUT_DIR / scene["output"]
        compose_scene(scene, render, output)
        print(output.relative_to(ROOT))


def run_render(exe, fixture, theme, output):
    cmd = [
        str(exe),
        "--shoot",
        str(fixture),
        "--theme",
        theme,
        "--width",
        "1540",
        "--height",
        "1280",
        "--out",
        str(output),
    ]
    subprocess.run(cmd, cwd=ROOT, check=True)


def compose_scene(scene, render_path, output_path):
    dark = scene["theme"] == "graphite"
    palette = dark_palette() if dark else light_palette()
    base = Image.new("RGB", (WIDTH, HEIGHT), palette["bg"])
    draw_background(base, palette)

    window = (170, 125, 2710, 1660)
    draw_window(base, window, scene, palette)

    render = Image.open(render_path).convert("RGB")
    if scene["id"] == "folder-workspace":
        draw_folder_workspace(base, window, render, palette)
    elif scene["id"] == "command-palette":
        draw_command_palette(base, window, render, palette)
    elif scene["id"] == "search-outline":
        draw_search_outline(base, window, render, palette)
    elif scene["id"] == "themed-export-readability":
        draw_themed_export(base, window, render, palette)
    else:
        raise ValueError(scene["id"])

    base.save(output_path, "PNG", optimize=True)


def light_palette():
    return {
        "bg": "#d7dee7",
        "bg2": "#eef2f7",
        "window": "#ffffff",
        "toolbar": "#f5f6f8",
        "border": "#c8d0da",
        "muted": "#687386",
        "text": "#172033",
        "sidebar": "#eef3f8",
        "sidebar2": "#f8fafc",
        "accent": "#1d63a5",
        "accent2": "#27876f",
        "selection": "#d7e9fb",
        "panel": "#ffffff",
        "shadow": (27, 38, 59, 72),
    }


def dark_palette():
    return {
        "bg": "#16181d",
        "bg2": "#222833",
        "window": "#2c2c2e",
        "toolbar": "#25272c",
        "border": "#484b52",
        "muted": "#a8adba",
        "text": "#f3f5f9",
        "sidebar": "#20242b",
        "sidebar2": "#262b33",
        "accent": "#71b6ff",
        "accent2": "#72d2ad",
        "selection": "#31455f",
        "panel": "#30333b",
        "shadow": (0, 0, 0, 115),
    }


def draw_background(image, palette):
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WIDTH, HEIGHT), fill=palette["bg"])
    draw.rounded_rectangle((118, 80, 2762, 1715), radius=58, fill=palette["bg2"])


def draw_window(image, box, scene, palette):
    x0, y0, x1, y1 = box
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle((x0 + 24, y0 + 30, x1 + 24, y1 + 30), radius=34, fill=palette["shadow"])
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    image.paste(Image.alpha_composite(image.convert("RGBA"), shadow).convert("RGB"))

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(box, radius=34, fill=palette["window"], outline=palette["border"], width=2)
    draw.rounded_rectangle((x0, y0, x1, y0 + 128), radius=34, fill=palette["toolbar"], outline=palette["border"], width=2)
    draw.rectangle((x0, y0 + 88, x1, y0 + 132), fill=palette["toolbar"])

    for index, color in enumerate(["#ff5f57", "#febc2e", "#28c840"]):
        draw.ellipse((x0 + 42 + index * 36, y0 + 40, x0 + 62 + index * 36, y0 + 60), fill=color)

    draw.text((x0 + 165, y0 + 31), "Ouro MD", fill=palette["text"], font=FONTS["toolbar"])
    draw.text((x0 + 350, y0 + 29), scene["title"], fill=palette["muted"], font=FONTS["toolbar"])
    draw.text((x0 + 1830, y0 + 30), scene["subtitle"], fill=palette["muted"], font=FONTS["sidebar_small"])

    pill(draw, (x0 + 1300, y0 + 24, x0 + 1495, y0 + 74), "Outline", palette)
    pill(draw, (x0 + 1512, y0 + 24, x0 + 1695, y0 + 74), "Search", palette)


def draw_folder_workspace(image, window, render, palette):
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = window
    content_top = y0 + 128
    sidebar = (x0, content_top, x0 + 560, y1)
    document = (x0 + 610, content_top + 80, x1 - 120, y1 - 115)

    draw.rectangle(sidebar, fill=palette["sidebar"])
    draw.line((sidebar[2], content_top, sidebar[2], y1), fill=palette["border"], width=2)
    draw.text((x0 + 52, content_top + 50), "Knowledge Base", fill=palette["text"], font=FONTS["sidebar_title"])
    tree_rows = [
        ("PROJECT", 0, False),
        ("  README.md", 1, True),
        ("  specs/", 1, False),
        ("    workspace-plan.md", 2, False),
        ("    release-notes.md", 2, False),
        ("  drafts/", 1, False),
        ("    api-review.md", 2, False),
        ("    export-checklist.md", 2, False),
    ]
    y = content_top + 120
    for label, indent, selected in tree_rows:
        if selected:
            draw.rounded_rectangle((x0 + 36, y - 12, x0 + 520, y + 30), radius=12, fill=palette["selection"])
        draw.text((x0 + 50 + indent * 22, y), label, fill=palette["text"] if selected else palette["muted"], font=FONTS["sidebar"])
        y += 56
    draw.text((x0 + 52, y1 - 190), "Local folder", fill=palette["muted"], font=FONTS["sidebar_small"])
    draw.text((x0 + 52, y1 - 150), "~/Documents/Ouro Workspace", fill=palette["text"], font=FONTS["mono"])

    draw_document_card(image, document, render, palette)


def draw_command_palette(image, window, render, palette):
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = window
    content_top = y0 + 128
    document = (x0 + 170, content_top + 86, x1 - 170, y1 - 115)
    draw_document_card(image, document, render, palette, dim=True)

    panel = (x0 + 650, y0 + 330, x1 - 650, y0 + 1040)
    panel_layer(image, panel, palette, radius=30)
    draw.text((panel[0] + 56, panel[1] + 45), "Command Palette", fill=palette["text"], font=FONTS["palette_title"])
    search = (panel[0] + 56, panel[1] + 112, panel[2] - 56, panel[1] + 185)
    draw.rounded_rectangle(search, radius=16, fill=palette["sidebar2"], outline=palette["border"], width=2)
    draw.text((search[0] + 28, search[1] + 21), "export", fill=palette["text"], font=FONTS["palette"])
    commands = [
        ("Export PDF", "File"),
        ("Export HTML", "File"),
        ("Open Folder", "Workspace"),
        ("Search Folder", "View"),
        ("Switch to Graphite", "Theme"),
        ("Show Keyboard Shortcuts", "Help"),
    ]
    y = panel[1] + 220
    for index, (name, group) in enumerate(commands):
        if index == 0:
            draw.rounded_rectangle((panel[0] + 42, y - 16, panel[2] - 42, y + 54), radius=16, fill=palette["selection"])
        draw.text((panel[0] + 70, y), name, fill=palette["text"], font=FONTS["palette"])
        draw.text((panel[2] - 280, y + 2), group, fill=palette["muted"], font=FONTS["sidebar"])
        y += 78


def draw_search_outline(image, window, render, palette):
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = window
    content_top = y0 + 128
    left = (x0, content_top, x0 + 520, y1)
    right = (x1 - 440, content_top, x1, y1)
    document = (left[2] + 56, content_top + 78, right[0] - 56, y1 - 115)

    draw.rectangle(left, fill=palette["sidebar"])
    draw.line((left[2], content_top, left[2], y1), fill=palette["border"], width=2)
    draw.text((left[0] + 52, content_top + 48), "Search", fill=palette["text"], font=FONTS["sidebar_title"])
    search_box = (left[0] + 48, content_top + 105, left[2] - 48, content_top + 162)
    draw.rounded_rectangle(search_box, radius=14, fill=palette["sidebar2"], outline=palette["border"], width=2)
    draw.text((search_box[0] + 18, search_box[1] + 15), "local", fill=palette["text"], font=FONTS["sidebar"])
    results = [
        ("workspace-plan.md", "Local files stay portable."),
        ("release-notes.md", "No account is required."),
        ("export-checklist.md", "Export PDF and HTML."),
        ("api-review.md", "Search across folders."),
    ]
    y = content_top + 205
    for index, (file, snippet) in enumerate(results):
        if index == 0:
            draw.rounded_rectangle((left[0] + 34, y - 12, left[2] - 34, y + 86), radius=16, fill=palette["selection"])
        draw.text((left[0] + 52, y), file, fill=palette["text"], font=FONTS["sidebar"])
        draw.text((left[0] + 52, y + 38), snippet, fill=palette["muted"], font=FONTS["sidebar_small"])
        y += 115

    draw.rectangle(right, fill=palette["sidebar2"])
    draw.line((right[0], content_top, right[0], y1), fill=palette["border"], width=2)
    draw.text((right[0] + 46, content_top + 48), "Outline", fill=palette["text"], font=FONTS["sidebar_title"])
    outline = ["Workspace notes", "Open local folders", "Search from the sidebar", "Export and handoff", "Review checklist"]
    y = content_top + 120
    for index, item in enumerate(outline):
        draw.text((right[0] + 48, y), item, fill=palette["text"] if index == 0 else palette["muted"], font=FONTS["sidebar"])
        y += 62

    draw_document_card(image, document, render, palette)


def draw_themed_export(image, window, render, palette):
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = window
    content_top = y0 + 128
    left = (x0, content_top, x0 + 470, y1)
    document = (left[2] + 70, content_top + 70, x1 - 560, y1 - 110)
    inspector = (x1 - 500, content_top + 82, x1 - 70, content_top + 745)

    draw.rectangle(left, fill=palette["sidebar"])
    draw.line((left[2], content_top, left[2], y1), fill=palette["border"], width=2)
    draw.text((left[0] + 50, content_top + 50), "Themes", fill=palette["text"], font=FONTS["sidebar_title"])
    for index, name in enumerate(["Quartz", "Graphite", "Manuscript", "Newsprint"]):
        y = content_top + 125 + index * 62
        if name == "Graphite":
            draw.rounded_rectangle((left[0] + 36, y - 12, left[2] - 36, y + 36), radius=14, fill=palette["selection"])
        draw.text((left[0] + 54, y), name, fill=palette["text"], font=FONTS["sidebar"])

    draw_document_card(image, document, render, palette)
    panel_layer(image, inspector, palette, radius=26)
    draw.text((inspector[0] + 42, inspector[1] + 44), "Export", fill=palette["text"], font=FONTS["palette_title"])
    for index, (label, detail) in enumerate([
        ("PDF", "Print-ready document"),
        ("HTML", "Self-contained file"),
        ("Markdown", "Keep the source"),
        ("No account", "Files stay local"),
    ]):
        y = inspector[1] + 125 + index * 110
        draw.rounded_rectangle((inspector[0] + 38, y - 16, inspector[2] - 38, y + 68), radius=18, fill=palette["sidebar2"], outline=palette["border"], width=1)
        draw.text((inspector[0] + 64, y), label, fill=palette["text"], font=FONTS["palette"])
        draw.text((inspector[0] + 64, y + 34), detail, fill=palette["muted"], font=FONTS["sidebar_small"])


def draw_document_card(image, box, render, palette, dim=False):
    draw = ImageDraw.Draw(image)
    panel_layer(image, box, palette, radius=22)
    inset = 28
    target = (box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset)
    resized = cover(render, target[2] - target[0], target[3] - target[1])
    image.paste(resized, target[:2])
    draw.rounded_rectangle(box, radius=22, outline=palette["border"], width=2)
    if dim:
        overlay = Image.new("RGBA", image.size, (16, 22, 32, 82))
        mask = Image.new("L", image.size, 0)
        mdraw = ImageDraw.Draw(mask)
        mdraw.rounded_rectangle(box, radius=22, fill=255)
        image.paste(Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB"), mask=mask)


def panel_layer(image, box, palette, radius=18):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rounded_rectangle((box[0] + 10, box[1] + 14, box[2] + 10, box[3] + 14), radius=radius, fill=palette["shadow"])
    overlay = overlay.filter(ImageFilter.GaussianBlur(12))
    image.paste(Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB"))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(box, radius=radius, fill=palette["panel"], outline=palette["border"], width=2)


def cover(image, width, height):
    ratio = max(width / image.width, height / image.height)
    resized = image.resize((round(image.width * ratio), round(image.height * ratio)), Image.Resampling.LANCZOS)
    left = max(0, (resized.width - width) // 2)
    return resized.crop((left, 0, left + width, height))


def pill(draw, box, label, palette):
    draw.rounded_rectangle(box, radius=16, fill=palette["sidebar2"], outline=palette["border"], width=1)
    draw.text((box[0] + 30, box[1] + 13), label, fill=palette["muted"], font=FONTS["sidebar_small"])


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc
