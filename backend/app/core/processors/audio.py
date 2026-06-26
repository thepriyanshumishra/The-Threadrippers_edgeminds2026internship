# app/core/processors/audio.py
# Purpose: Audio transcription and chunking pipeline using faster-whisper.
# Responsibilities: Uses local faster-whisper model to transcribe audio, maps character chunks to timestamps, saves chunks, and returns stats.

import os
import json
import logging
from pathlib import Path
from typing import Dict, Any, List

# Prevent OpenMP runtime conflict on Intel Mac before importing Whisper/torch
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

from app.core.config import settings
from app.core.processors.text import find_chunk_boundaries, find_parent_child_boundaries

logger = logging.getLogger("kivo.processors.audio")

class AudioProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def create_chunks_from_segments(self, segments: List[Any], duration: float, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Takes raw segments (dicts or objects), maps character ranges to timestamps,
        generates overlapping chunks, saves the chunks to SQLite, and returns stats.
        """
        # 1. Convert segments to uniform dictionaries: {"text": str, "start": float, "end": float}
        uniform_segments = []
        for seg in segments:
            if isinstance(seg, dict):
                text = seg.get("text", "")
                start = seg.get("start", 0.0)
                end = seg.get("end", 0.0)
            else:
                text = getattr(seg, "text", "")
                start = getattr(seg, "start", 0.0)
                end = getattr(seg, "end", 0.0)
            
            if text.strip():
                uniform_segments.append({
                    "text": text,
                    "start": start,
                    "end": end
                })

        # 2. Concatenate segment texts and map character indices back to segment timestamps
        concatenated_text = ""
        char_ranges = []  # list of (start_char_idx, end_char_idx, start_time, end_time)
        
        for segment in uniform_segments:
            seg_text = segment["text"]
            
            # Add a leading space if it is not the first segment
            if concatenated_text:
                seg_text = " " + seg_text.lstrip()
            else:
                seg_text = seg_text.lstrip()
                
            start_idx = len(concatenated_text)
            concatenated_text += seg_text
            end_idx = len(concatenated_text)
            
            char_ranges.append((
                start_idx,
                end_idx,
                segment["start"],
                segment["end"]
            ))
            
        clean_text = concatenated_text.strip()
        total_words = len(clean_text.split())
        total_chars = len(clean_text)
        
        # Helper to map chunk range to start/end timestamps
        def get_timestamps_for_range(start_char: int, end_char: int) -> tuple:
            chunk_start = None
            chunk_end = None
            
            for start_idx, end_idx, start_time, end_time in char_ranges:
                if start_idx <= start_char < end_idx or (chunk_start is None and start_idx >= start_char):
                    if chunk_start is None:
                        chunk_start = start_time
                if start_idx < end_char <= end_idx or end_idx <= end_char:
                    chunk_end = end_time
                    
            if chunk_start is None:
                chunk_start = char_ranges[0][2] if char_ranges else 0.0
            if chunk_end is None:
                chunk_end = char_ranges[-1][3] if char_ranges else duration
                
            return chunk_start, chunk_end

        # 3. Chunk transcript using boundary-aware splitter
        child_chunks = []
        parent_texts = []
        child_idx = 0
        
        if clean_text:
            parent_texts, child_boundaries = find_parent_child_boundaries(
                clean_text,
                parent_size=self.chunk_size,
                parent_overlap=self.chunk_overlap
            )
            for start_idx, end_idx, parent_idx in child_boundaries:
                chunk_text = clean_text[start_idx:end_idx].strip()
                if chunk_text:
                    chunk_start, chunk_end = get_timestamps_for_range(start_idx, end_idx)
                    child_chunks.append({
                        "index": child_idx,
                        "text": chunk_text,
                        "metadata": {
                            "start_time": chunk_start,
                            "end_time": chunk_end,
                            "parent_id": parent_idx
                        }
                    })
                    child_idx += 1
                    
        # 4. Save chunks to SQLite database
        from app.core.database import save_chunks_to_db
        save_chunks_to_db(workspace_id, source_id, parent_texts, child_chunks)
            
        # 5. Generate summary preview (first 300 characters of the document)
        summary = clean_text[:300].strip() + ("..." if total_chars > 300 else "")
        
        logger.info(f"Generated {len(child_chunks)} child chunks, {len(parent_texts)} parent chunks, {total_words} words for source {source_id}.")
        return {
            "stats": {
                "duration": duration,
                "words": total_words,
                "chunks": len(child_chunks)
            },
            "summary": summary
        }

    def process(self, file_path: Path, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Transcribes audio using local faster-whisper, splits transcript into overlapping chunks,
        saves chunks to disk, and returns stats.
        """
        logger.info(f"Processing Audio file: {file_path}")
        
        if not file_path.exists():
            raise FileNotFoundError(f"Audio file not found at {file_path}")
            
        # 1. Load faster-whisper Model and Transcribe
        try:
            from faster_whisper import WhisperModel
            
            logger.info(f"Loading faster-whisper model '{settings.whisper_model}' (INT8 CPU)...")
            model = WhisperModel(settings.whisper_model, device="cpu", compute_type="int8", cpu_threads=4)
            
            logger.info("Transcribing audio...")
            segments_generator, info = model.transcribe(
                str(file_path),
                beam_size=5,
                vad_filter=True,
                condition_on_previous_text=False
            )
            segments = list(segments_generator)
            duration = info.duration
            logger.info(f"Transcription finished. Duration: {duration:.2f}s, Language: {info.language}")
        except Exception as e:
            logger.error(f"Failed to transcribe audio file {file_path}: {e}")
            raise RuntimeError(f"Transcription failed: {e}")
            
        # 2. Map and chunk via helper
        return self.create_chunks_from_segments(segments, duration, workspace_id, source_id)
