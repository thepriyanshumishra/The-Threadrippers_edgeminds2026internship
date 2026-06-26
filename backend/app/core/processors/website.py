# app/core/processors/website.py
# Purpose: Web page content extraction and chunking pipeline.
# Responsibilities:
#   1. Uses Playwright (headless Chromium) to fully render any webpage,
#      including JavaScript-driven SPAs (React, Vue, Next.js, Angular).
#   2. Passes the fully rendered DOM to readability-lxml (Mozilla Firefox
#      Reader Mode algorithm) for algorithmic, layout-agnostic boilerplate
#      stripping (menus, navbars, footers, sidebars, ads).
#   3. Converts the isolated main content to clean, human-readable plaintext,
#      preserving table structures as tab-separated rows.
#   4. Chunks the result into overlapping segments and saves to disk.

import json
import logging
from pathlib import Path
from typing import Dict, Any

from bs4 import BeautifulSoup
from readability import Document

from app.core.config import settings
from app.core.processors.text import find_chunk_boundaries, find_parent_child_boundaries

logger = logging.getLogger("kivo.processors.website")


class WebsiteProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def _node_to_clean_text(self, element) -> str:
        """
        Recursively converts a BeautifulSoup element to clean, human-readable
        plain text. Handles tables (tab-separated rows), lists, and paragraphs.
        Strips all raw HTML tags and inline links.
        """
        if not element:
            return ""

        # Skip boilerplate tags that readability may have missed
        if element.name in ["script", "style", "nav", "footer", "header", "aside", "iframe", "noscript"]:
            return ""

        # Format <table> as tab-separated values for readability in LLMs
        if element.name == "table":
            table_lines = []
            for row in element.find_all("tr"):
                cells = row.find_all(["td", "th"], recursive=False)
                if not cells:
                    continue
                row_cells = [" ".join(cell.get_text().split()) for cell in cells]
                table_lines.append("\t".join(row_cells))
            return "\n".join(table_lines) + "\n" if table_lines else ""

        # Plain string navigation node
        if hasattr(element, "name") and element.name is None:
            # NavigableString
            return str(element)

        # Recurse into children
        text_parts = []
        for child in element.children:
            child_text = self._node_to_clean_text(child)
            if child_text:
                text_parts.append(child_text)

        name = element.name

        if name in ["p", "div", "section", "article", "blockquote", "pre"]:
            joined = "".join(text_parts)
            return joined.strip() + "\n"
        elif name in ["h1", "h2", "h3", "h4", "h5", "h6"]:
            joined = "".join(text_parts)
            return "\n" + joined.strip() + "\n"
        elif name == "li":
            joined = "".join(text_parts)
            return "• " + joined.strip() + "\n"
        elif name in ["ul", "ol"]:
            return "".join(text_parts)
        elif name == "br":
            return "\n"
        elif name == "tr":
            return "".join(text_parts).strip() + "\n"
        elif name in ["td", "th"]:
            return " ".join("".join(text_parts).split()) + "\t"
        else:
            return "".join(text_parts)

    def _fetch_rendered_html(self, url: str) -> str:
        """
        Uses a synchronous Playwright call to launch a headless Chromium browser,
        navigate to the URL, wait for the page to fully render (networkidle),
        and return the full rendered HTML DOM string.
        """
        # Use sync_playwright to avoid asyncio event loop conflicts with FastAPI/uvicorn
        from playwright.sync_api import sync_playwright

        logger.info(f"Launching headless browser for: {url}")
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent=(
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) "
                    "Chrome/120.0.0.0 Safari/537.36"
                ),
                viewport={"width": 1280, "height": 800},
            )
            page = context.new_page()

            # Block image, font, and media downloads to speed up extraction
            page.route(
                "**/*",
                lambda route: route.abort()
                if route.request.resource_type in ["image", "media", "font", "stylesheet"]
                else route.continue_(),
            )

            try:
                page.goto(url, wait_until="domcontentloaded", timeout=30_000)
                # Give JS frameworks up to 8s to finish rendering.
                # Many ad-heavy sites never fully reach networkidle — cap the wait.
                try:
                    page.wait_for_load_state("networkidle", timeout=8_000)
                except Exception:
                    # Timed out waiting for network idle — this is expected on ad/tracker-heavy
                    # sites (e.g. W3Schools). The DOM content is already loaded, so we proceed.
                    logger.info(f"Network idle not reached for {url}; proceeding with current DOM.")
            except Exception as e:
                logger.warning(f"Page navigation failed (proceeding with partial DOM): {e}")

            html = page.content()
            browser.close()

        logger.info(f"Successfully rendered page: {url} ({len(html)} bytes of HTML)")
        return html

    def process(self, url: str, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Main pipeline:
          1. Render the page fully in headless Chromium (Playwright).
          2. Pass the HTML to Mozilla Readability (readability-lxml) to algorithmically
             isolate and return only the main article body.
          3. Convert the clean HTML fragment to plain text, preserving table structure.
          4. Chunk the text and persist to disk.
        """
        logger.info(f"Processing Website URL: {url}")

        # ── Step 1: Render with Playwright ───────────────────────────────────
        try:
            raw_html = self._fetch_rendered_html(url)
        except Exception as e:
            logger.error(f"Failed to render webpage at {url}: {e}")
            raise RuntimeError(f"Failed to render webpage: {e}")

        # ── Step 2: Mozilla Readability — extract main content ────────────────
        try:
            doc = Document(raw_html)
            page_title = doc.title() or "Website Source"
            # doc.summary() returns a clean HTML fragment of the main body
            readable_html = doc.summary(html_partial=True)
        except Exception as e:
            logger.warning(f"Readability failed, falling back to raw body: {e}")
            soup_fallback = BeautifulSoup(raw_html, "html.parser")
            readable_html = str(soup_fallback.body) if soup_fallback.body else raw_html
            page_title = soup_fallback.title.string.strip() if soup_fallback.title else "Website Source"

        # ── Step 3: Parse & convert to plain text ─────────────────────────────
        soup = BeautifulSoup(readable_html, "html.parser")

        # Remove any remaining boilerplate that readability may have kept
        for tag in soup(["script", "style", "nav", "footer", "header", "aside", "iframe", "noscript"]):
            tag.decompose()

        try:
            raw_text = self._node_to_clean_text(soup)
        except Exception as e:
            logger.error(f"Error converting HTML to text: {e}")
            raw_text = soup.get_text(separator="\n")

        # Post-process: collapse excessive blank lines, trim whitespace
        raw_lines = raw_text.splitlines()
        cleaned_lines = []
        prev_blank = False
        for line in raw_lines:
            stripped = line.strip()
            if stripped:
                # Preserve tab-separated table rows
                if "\t" in line:
                    parts = [p.strip() for p in line.split("\t") if p.strip()]
                    cleaned_lines.append("\t".join(parts))
                else:
                    cleaned_lines.append(stripped)
                prev_blank = False
            else:
                if not prev_blank:
                    cleaned_lines.append("")
                prev_blank = True

        final_text = "\n".join(cleaned_lines).strip()

        if not final_text:
            final_text = f"No readable content could be extracted from: {url}"

        # ── Step 4: Chunk text ────────────────────────────────────────────────
        child_chunks = []
        parent_texts = []
        child_idx = 0

        if final_text:
            parent_texts, child_boundaries = find_parent_child_boundaries(
                final_text,
                parent_size=self.chunk_size,
                parent_overlap=self.chunk_overlap
            )
            for start_idx, end_idx, parent_idx in child_boundaries:
                chunk_text = final_text[start_idx:end_idx].strip()
                if chunk_text:
                    child_chunks.append({
                        "index": child_idx,
                        "text": chunk_text,
                        "metadata": {
                            "url": url,
                            "parent_id": parent_idx
                        }
                    })
                    child_idx += 1

        # ── Step 5: Save chunks to SQLite database ─────────────────────────────
        from app.core.database import save_chunks_to_db
        save_chunks_to_db(workspace_id, source_id, parent_texts, child_chunks)

        summary = final_text[:300].strip() + ("..." if len(final_text) > 300 else "")
        total_words = len(final_text.split())

        logger.info(
            f"Website processed: '{page_title}' | {total_words} words | {len(child_chunks)} child chunks | {len(parent_texts)} parent chunks"
        )

        return {
            "title": page_title,
            "stats": {
                "pages": 1,
                "words": total_words,
                "chunks": len(child_chunks)
            },
            "summary": summary
        }
