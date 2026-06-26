# app/core/processors/pdf.py
# Purpose: PDF text extraction and chunking pipeline.
# Responsibilities: Uses PyMuPDF (fitz) to extract text page-by-page, chunk it, and save chunks to disk.

import fitz  # PyMuPDF
import json
import logging
from pathlib import Path
from typing import Dict, Any, List

from app.core.processors.text import find_chunk_boundaries, find_parent_child_boundaries

logger = logging.getLogger("kivo.processors.pdf")

class PDFProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def process(self, file_path: Path, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Extracts text from PDF, splits it into overlapping chunks page-by-page,
        saves chunks to disk, and returns statistics and preview summary.
        """
        logger.info(f"Processing PDF file: {file_path}")
        
        if not file_path.exists():
            raise FileNotFoundError(f"PDF file not found at {file_path}")
            
        try:
            doc = fitz.open(file_path)
            page_count = len(doc)
        except Exception as e:
            logger.error(f"PyMuPDF failed to open PDF {file_path}: {e}")
            raise ValueError(f"Failed to open PDF file. The file may be corrupted or encrypted. Details: {e}")
            
        total_words = 0
        total_chars = 0
        
        # 1. Extract text page by page
        pages_text = []
        try:
            for page_num in range(page_count):
                page = doc[page_num]
                text = page.get_text("text")  # Extract clean layout text
                pages_text.append(text)
                
                # Update stats
                total_words += len(text.split())
                total_chars += len(text)
        except Exception as e:
            doc.close()
            logger.error(f"Failed to extract text from PDF {file_path}: {e}")
            raise ValueError(f"Failed to read text pages from PDF. Details: {e}")
            
        # Check if any text was extracted
        if total_chars == 0:
            doc.close()
            logger.warning(f"PDF file {file_path} contains no readable text (could be scanned document or empty).")
            # Return empty stats instead of crashing
            return {
                "stats": {
                    "pages": page_count,
                    "words": 0,
                    "chunks": 0
                },
                "summary": "This document contains no readable text. (If it is a scanned document, please upload it as an Image source for OCR)."
            }
            
        # 2. Chunk text page-by-page to preserve precise page boundaries for citations
        child_chunks = []
        parent_texts = []
        child_idx = 0
        
        for page_num, page_text in enumerate(pages_text):
            if not page_text.strip():
                continue
                
            parent_offset = len(parent_texts)
            
            page_parents, page_children_boundaries = find_parent_child_boundaries(
                page_text,
                parent_size=self.chunk_size,
                parent_overlap=self.chunk_overlap
            )
            
            parent_texts.extend(page_parents)
            
            for c_start, c_end, rel_p_idx in page_children_boundaries:
                chunk_text = page_text[c_start:c_end].strip()
                if chunk_text:
                    child_chunks.append({
                        "index": child_idx,
                        "text": chunk_text,
                        "metadata": {
                            "page": page_num + 1,
                            "parent_id": parent_offset + rel_p_idx
                        }
                    })
                    child_idx += 1
                
        # Save chunks to SQLite database
        from app.core.database import save_chunks_to_db
        try:
            save_chunks_to_db(workspace_id, source_id, parent_texts, child_chunks)
        except Exception as e:
            doc.close()
            logger.error(f"Failed to save PDF chunks to database: {e}")
            raise RuntimeError(f"Database error while saving PDF chunks: {e}")
            
        # 4. Generate summary preview (first 300 characters of the document)
        preview_text = ""
        for page_text in pages_text:
            if page_text.strip():
                preview_text += page_text.strip() + " "
                if len(preview_text) > 300:
                    break
        summary = preview_text[:300].strip() + ("..." if len(preview_text) > 300 else "")
        
        doc.close()
        
        logger.info(f"PDF processed: {page_count} pages, {total_words} words, {len(child_chunks)} child chunks, {len(parent_texts)} parent chunks generated.")
        return {
            "stats": {
                "pages": page_count,
                "words": total_words,
                "chunks": len(child_chunks)
            },
            "summary": summary
        }
