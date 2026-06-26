# app/core/processors/text.py
# Purpose: Copied text content chunking pipeline.
# Responsibilities: Reads saved raw copied text, chunks it, and saves the chunks to disk.

import json
import logging
import re
from pathlib import Path
from typing import Dict, Any, List

from app.core.config import settings

logger = logging.getLogger("kivo.processors.text")

def find_chunk_boundaries(text: str, chunk_size: int = 1000, chunk_overlap: int = 200) -> List[tuple]:
    """
    Finds boundary-aware start and end character indices for chunks of approximately chunk_size.
    Preserves words, sentence boundaries, and paragraph boundaries.
    """
    text_len = len(text)
    if text_len <= chunk_size:
        return [(0, text_len)] if text_len > 0 else []

    sentence_split_regex = re.compile(r'(?<=[.!?])\s+')
    spans = []
    paragraphs = text.split("\n\n")
    current_offset = 0
    
    for p in paragraphs:
        p_len = len(p)
        if p_len == 0:
            current_offset += 2  # Length of \n\n
            continue
        
        sentences = sentence_split_regex.split(p)
        p_offset = 0
        for s in sentences:
            if not s.strip():
                continue
            start_in_p = p.find(s, p_offset)
            if start_in_p == -1:
                start_in_p = p_offset
            end_in_p = start_in_p + len(s)
            p_offset = end_in_p
            
            global_start = current_offset + start_in_p
            global_end = current_offset + end_in_p
            spans.append((global_start, global_end))
            
        current_offset += p_len + 2
        
    if not spans:
        return [(0, text_len)] if text_len > 0 else []
        
    chunks = []
    current_chunk_spans = []
    current_len = 0
    
    idx = 0
    while idx < len(spans):
        span_start, span_end = spans[idx]
        span_len = span_end - span_start
        
        # If a single sentence span is larger than chunk_size, split by words
        if span_len > chunk_size:
            if current_chunk_spans:
                chunks.append((current_chunk_spans[0][0], current_chunk_spans[-1][1]))
                current_chunk_spans = []
                current_len = 0
            
            word_spans = []
            word_offset = span_start
            sentence_text = text[span_start:span_end]
            words = sentence_text.split(" ")
            for w in words:
                if not w:
                    continue
                w_start = sentence_text.find(w, word_offset - span_start)
                if w_start == -1:
                    w_start = word_offset - span_start
                w_start += span_start
                w_end = w_start + len(w)
                word_offset = w_end
                word_spans.append((w_start, w_end))
                
            w_idx = 0
            while w_idx < len(word_spans):
                w_start, w_end = word_spans[w_idx]
                w_len = w_end - w_start
                
                if current_len + w_len + (1 if current_chunk_spans else 0) > chunk_size and current_chunk_spans:
                    chunks.append((current_chunk_spans[0][0], current_chunk_spans[-1][1]))
                    overlap_spans = []
                    overlap_len = 0
                    for os in reversed(current_chunk_spans):
                        os_len = os[1] - os[0]
                        if overlap_len + os_len + (1 if overlap_spans else 0) <= chunk_overlap:
                            overlap_spans.insert(0, os)
                            overlap_len += os_len + 1
                        else:
                            break
                    current_chunk_spans = overlap_spans
                    current_len = overlap_len
                    
                current_chunk_spans.append((w_start, w_end))
                current_len += w_len + 1
                w_idx += 1
            idx += 1
            continue
            
        # Normal sentence span grouping
        if current_len + span_len + (1 if current_chunk_spans else 0) > chunk_size and current_chunk_spans:
            chunks.append((current_chunk_spans[0][0], current_chunk_spans[-1][1]))
            overlap_spans = []
            overlap_len = 0
            for os in reversed(current_chunk_spans):
                os_len = os[1] - os[0]
                if overlap_len + os_len + (1 if overlap_spans else 0) <= chunk_overlap:
                    overlap_spans.insert(0, os)
                    overlap_len += os_len + 1
                else:
                    break
            current_chunk_spans = overlap_spans
            current_len = overlap_len
            
        current_chunk_spans.append((span_start, span_end))
        current_len += span_len + (1 if len(current_chunk_spans) > 1 else 0)
        idx += 1
        
    if current_chunk_spans:
        chunks.append((current_chunk_spans[0][0], current_chunk_spans[-1][1]))
        
    return chunks

def find_parent_child_boundaries(text: str, parent_size: int = 1000, parent_overlap: int = 200, child_size: int = 750, child_overlap: int = 150) -> tuple:
    """
    Finds boundary-aware parent and child chunk boundaries.
    Returns:
        parent_texts: List[str] - The text of each parent chunk.
        child_boundaries: List[tuple] - List of (c_start_global, c_end_global, parent_id)
    """
    parent_boundaries = find_chunk_boundaries(text, parent_size, parent_overlap)
    parent_texts = []
    child_boundaries = []
    
    for p_idx, (p_start, p_end) in enumerate(parent_boundaries):
        p_text = text[p_start:p_end]
        parent_texts.append(p_text.strip())
        
        # Split parent into child boundaries
        c_boundaries = find_chunk_boundaries(p_text, child_size, child_overlap)
        for c_start_rel, c_end_rel in c_boundaries:
            c_start_global = p_start + c_start_rel
            c_end_global = p_start + c_end_rel
            child_boundaries.append((c_start_global, c_end_global, p_idx))
            
    return parent_texts, child_boundaries


class TextProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200, child_size: int = 750, child_overlap: int = 150):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap
        self.child_size = child_size
        self.child_overlap = child_overlap

    def process(self, file_path: Path, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Reads raw copied text, splits it into overlapping parent-child chunks,
        saves child and parent chunks to disk, and returns statistics and preview summary.
        """
        logger.info(f"Processing Text file: {file_path}")
        
        if not file_path.exists():
            raise FileNotFoundError(f"Text file not found at {file_path}")
            
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read().strip()
        except Exception as e:
            logger.error(f"Failed to read text file at {file_path}: {e}")
            raise RuntimeError(f"Failed to read text file: {e}")
            
        if not content:
            content = "Empty text content."
            
        # Split text into overlapping parent-child chunks
        parent_texts, child_boundaries = find_parent_child_boundaries(
            content,
            parent_size=self.chunk_size,
            parent_overlap=self.chunk_overlap,
            child_size=self.child_size,
            child_overlap=self.child_overlap
        )
        
        child_chunks = []
        for idx, (start_idx, end_idx, parent_idx) in enumerate(child_boundaries):
            chunk_text = content[start_idx:end_idx].strip()
            if chunk_text:
                child_chunks.append({
                    "index": idx,
                    "text": chunk_text,
                    "metadata": {
                        "source": "pasted_text",
                        "parent_id": parent_idx
                    }
                })
            
        # Save chunks to SQLite database
        from app.core.database import save_chunks_to_db
        save_chunks_to_db(workspace_id, source_id, parent_texts, child_chunks)
            
        summary = content[:300].strip() + ("..." if len(content) > 300 else "")
        total_words = len(content.split())
        
        logger.info(f"Text processed: {total_words} words, {len(child_chunks)} child chunks, {len(parent_texts)} parent chunks generated.")
        
        return {
            "stats": {
                "pages": 1,  # Text documents are represented as a single virtual page
                "words": total_words,
                "chunks": len(child_chunks)
            },
            "summary": summary
        }

