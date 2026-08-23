#!/usr/bin/env python3
"""Build the Xiaotiancai submission PDFs from the reviewed Markdown sources."""

from __future__ import annotations

import html
import re
import sys
import types
from pathlib import Path

# ReportLab imports Pillow for optional image handling. This submission builder is
# text-only, so keep it runnable in the controlled build venv without Pillow.
try:
    import PIL  # noqa: F401
except ModuleNotFoundError:
    pil_module = types.ModuleType("PIL")
    image_module = types.ModuleType("PIL.Image")
    pil_module.Image = image_module
    sys.modules["PIL"] = pil_module
    sys.modules["PIL.Image"] = image_module

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    ListFlowable,
    ListItem,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

GREEN = colors.HexColor("#16643A")
GREEN_LIGHT = colors.HexColor("#EAF5EE")
TEXT = colors.HexColor("#20332A")
MUTED = colors.HexColor("#5B7161")
GRID = colors.HexColor("#CFE1D6")


def inline_markup(value: str) -> str:
    value = html.escape(value.strip())
    value = re.sub(r"`([^`]+)`", r'<font color="#285E45">\1</font>', value)
    value = re.sub(r"&lt;(https?://[^&]+)&gt;", r"\1", value)
    value = re.sub(r"\[([^]]+)\]\((https?://[^)]+)\)", r"\1 (\2)", value)
    return value


class SubmissionDoc(BaseDocTemplate):
    def __init__(self, output: Path, title: str, landscape_mode: bool = False):
        page_size = landscape(A4) if landscape_mode else A4
        super().__init__(
            str(output),
            pagesize=page_size,
            leftMargin=18 * mm,
            rightMargin=18 * mm,
            topMargin=18 * mm,
            bottomMargin=17 * mm,
            title=title,
            author="厦门图灵软件有限公司",
            subject="家加分手表积分小天才应用市场提审材料",
        )
        frame = Frame(
            self.leftMargin,
            self.bottomMargin,
            self.width,
            self.height,
            leftPadding=0,
            rightPadding=0,
            topPadding=0,
            bottomPadding=0,
        )
        self.addPageTemplates(PageTemplate(id="body", frames=[frame], onPage=self.draw_page))

    def draw_page(self, canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(GRID)
        canvas.setLineWidth(0.6)
        canvas.line(self.leftMargin, 12 * mm, self.pagesize[0] - self.rightMargin, 12 * mm)
        canvas.setFont("STSong-Light", 8)
        canvas.setFillColor(MUTED)
        canvas.drawString(self.leftMargin, 7.5 * mm, "厦门图灵软件有限公司 | 家加分手表积分 1.0.0")
        canvas.drawRightString(self.pagesize[0] - self.rightMargin, 7.5 * mm, f"第 {doc.page} 页")
        canvas.restoreState()


def make_styles():
    base = getSampleStyleSheet()
    styles = {
        "title": ParagraphStyle(
            "DocTitle",
            parent=base["Title"],
            fontName="STSong-Light",
            fontSize=22,
            leading=30,
            textColor=GREEN,
            alignment=TA_LEFT,
            spaceAfter=10,
        ),
        "h1": ParagraphStyle(
            "Heading1CN",
            parent=base["Heading1"],
            fontName="STSong-Light",
            fontSize=15,
            leading=21,
            textColor=GREEN,
            spaceBefore=12,
            spaceAfter=6,
            keepWithNext=True,
        ),
        "h2": ParagraphStyle(
            "Heading2CN",
            parent=base["Heading2"],
            fontName="STSong-Light",
            fontSize=12,
            leading=18,
            textColor=colors.HexColor("#A94A27"),
            spaceBefore=9,
            spaceAfter=4,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "BodyCN",
            parent=base["BodyText"],
            fontName="STSong-Light",
            fontSize=9.5,
            leading=15.5,
            textColor=TEXT,
            spaceAfter=5,
            wordWrap="CJK",
        ),
        "small": ParagraphStyle(
            "SmallCN",
            parent=base["BodyText"],
            fontName="STSong-Light",
            fontSize=7.2,
            leading=10.5,
            textColor=TEXT,
            wordWrap="CJK",
        ),
        "table_header": ParagraphStyle(
            "TableHeaderCN",
            parent=base["BodyText"],
            fontName="STSong-Light",
            fontSize=7.6,
            leading=10.5,
            textColor=colors.white,
            wordWrap="CJK",
        ),
        "code": ParagraphStyle(
            "CodeCN",
            parent=base["BodyText"],
            fontName="STSong-Light",
            fontSize=9,
            leading=14.5,
            textColor=TEXT,
            leftIndent=5 * mm,
            rightIndent=5 * mm,
            borderColor=GRID,
            borderWidth=0.7,
            borderPadding=7,
            backColor=colors.HexColor("#F5F8F6"),
            spaceBefore=4,
            spaceAfter=7,
            wordWrap="CJK",
        ),
        "list": ParagraphStyle(
            "ListCN",
            parent=base["BodyText"],
            fontName="STSong-Light",
            fontSize=9.5,
            leading=15.5,
            textColor=TEXT,
            wordWrap="CJK",
        ),
    }
    return styles


def parse_table(lines: list[str], styles, available_width: float):
    rows = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
            continue
        rows.append(cells)
    columns = max(len(row) for row in rows)
    for row in rows:
        row.extend([""] * (columns - len(row)))

    font_style = styles["small"] if columns >= 5 else styles["body"]
    data = []
    for row_index, row in enumerate(rows):
        row_style = styles["table_header"] if row_index == 0 else font_style
        data.append([Paragraph(inline_markup(cell), row_style) for cell in row])
    if columns == 4:
        widths = [available_width * x for x in (0.12, 0.22, 0.16, 0.50)]
    elif columns == 3:
        widths = [available_width * x for x in (0.24, 0.36, 0.40)]
    elif columns == 2:
        widths = [available_width * 0.28, available_width * 0.72]
    else:
        widths = [available_width / columns] * columns

    table = Table(data, colWidths=widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), GREEN),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, -1), "STSong-Light"),
                ("GRID", (0, 0), (-1, -1), 0.45, GRID),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GREEN_LIGHT]),
            ]
        )
    )
    return table


def markdown_story(source: Path, styles, available_width: float, subtitle_date: str):
    lines = source.read_text(encoding="utf-8").splitlines()
    story = []
    index = 0
    first_title = True
    in_code = False
    code_lines: list[str] = []

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if stripped.startswith("```"):
            if in_code:
                story.append(Paragraph("<br/>".join(inline_markup(x) for x in code_lines), styles["code"]))
                code_lines = []
                in_code = False
            else:
                in_code = True
            index += 1
            continue
        if in_code:
            code_lines.append(line)
            index += 1
            continue
        if not stripped:
            index += 1
            continue
        if stripped.startswith("|") and index + 1 < len(lines) and lines[index + 1].strip().startswith("|"):
            table_lines = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                table_lines.append(lines[index])
                index += 1
            story.append(parse_table(table_lines, styles, available_width))
            story.append(Spacer(1, 6))
            continue
        heading = re.match(r"^(#{1,3})\s+(.+)$", stripped)
        if heading:
            level = len(heading.group(1))
            if level == 1 and first_title:
                story.append(Paragraph(inline_markup(heading.group(2)), styles["title"]))
                story.append(Paragraph(f"小天才应用市场提审材料 | {subtitle_date}", styles["body"]))
                story.append(Spacer(1, 4))
                first_title = False
            else:
                story.append(Paragraph(inline_markup(heading.group(2)), styles["h1"] if level <= 2 else styles["h2"]))
            index += 1
            continue
        if re.match(r"^[-*]\s+", stripped):
            items = []
            while index < len(lines) and re.match(r"^[-*]\s+", lines[index].strip()):
                item = re.sub(r"^[-*]\s+", "", lines[index].strip())
                items.append(ListItem(Paragraph(inline_markup(item), styles["list"]), leftIndent=7 * mm))
                index += 1
            story.append(ListFlowable(items, bulletType="bullet", start="circle", leftIndent=8 * mm, bulletFontName="STSong-Light"))
            story.append(Spacer(1, 4))
            continue
        if re.match(r"^\d+\.\s+", stripped):
            items = []
            while index < len(lines) and re.match(r"^\d+\.\s+", lines[index].strip()):
                item = re.sub(r"^\d+\.\s+", "", lines[index].strip())
                items.append(ListItem(Paragraph(inline_markup(item), styles["list"]), leftIndent=8 * mm))
                index += 1
            story.append(ListFlowable(items, bulletType="1", leftIndent=9 * mm, bulletFontName="STSong-Light"))
            story.append(Spacer(1, 4))
            continue

        paragraph_lines = [stripped]
        index += 1
        while index < len(lines):
            candidate = lines[index].strip()
            if not candidate or candidate.startswith("#") or candidate.startswith("|") or candidate.startswith("```"):
                break
            if re.match(r"^[-*]\s+|^\d+\.\s+", candidate):
                break
            paragraph_lines.append(candidate)
            index += 1
        story.append(Paragraph(inline_markup(" ".join(paragraph_lines)), styles["body"]))

    return story


def build(source: Path, output: Path, landscape_mode: bool = False):
    styles = make_styles()
    source_text = source.read_text(encoding="utf-8")
    title = source_text.splitlines()[0].lstrip("# ")
    test_date = re.search(r"\|\s*测试日期\s*\|\s*(\d{4})-(\d{2})-(\d{2})\s*\|", source_text)
    subtitle_date = (
        f"{test_date.group(1)}年{int(test_date.group(2))}月{int(test_date.group(3))}日"
        if test_date
        else "2026年8月20日"
    )
    doc = SubmissionDoc(output, title, landscape_mode)
    doc.build(markdown_story(source, styles, doc.width, subtitle_date))


def main(repo: Path):
    source_dir = repo / "docs/publishing/xiaotiancai"
    output_dir = source_dir / "release-bundle"
    output_dir.mkdir(parents=True, exist_ok=True)
    jobs = [
        ("04-privacy-policy-draft.md", "家加分手表积分_隐私政策.pdf", False),
        ("05-user-agreement-draft.md", "家加分手表积分_用户协议.pdf", False),
        ("06-disclaimer-draft.md", "家加分手表积分_首次提交免责函_待盖章.pdf", False),
        ("03-test-cases-and-report.md", "家加分手表积分_测试报告.pdf", False),
        ("12-server-performance-report.md", "家加分手表积分_服务器性能报告.pdf", True),
        ("02-review-user-guide.md", "家加分手表积分_客服审核使用说明.pdf", False),
    ]
    for source_name, output_name, landscape_mode in jobs:
        output = output_dir / output_name
        build(source_dir / source_name, output, landscape_mode)
        print(output)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: build-xiaotiancai-pdfs.py <repo-root>")
    pdfmetrics.registerFont(UnicodeCIDFont("STSong-Light"))
    main(Path(sys.argv[1]).resolve())
