# app/core/processors/image.py
# Purpose: Image OCR text extraction and chunking pipeline.
# Responsibilities: Uses Pillow to read dimensions, pytesseract to run OCR, chunks text, and saves chunks to disk.

from PIL import Image
import json
import logging
from pathlib import Path
from typing import Dict, Any

from app.core.processors.text import find_chunk_boundaries, find_parent_child_boundaries

logger = logging.getLogger("kivo.processors.image")

class ImageProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def process(self, file_path: Path, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Extracts text from an image using OCR (RapidOCR), splits it into overlapping chunks,
        saves chunks to disk, and returns statistics and preview summary.
        """
        logger.info(f"Processing Image file: {file_path}")
        
        if not file_path.exists():
            raise FileNotFoundError(f"Image file not found at {file_path}")
            
        # 1. Open image and get dimensions & extract text via OCR
        try:
            try:
                from rapidocr_onnxruntime import RapidOCR
            except ImportError:
                from app.core.exceptions import DepsRequiredException
                raise DepsRequiredException(
                    ["rapidocr-onnxruntime"],
                    message="Image OCR processing requires the 'rapidocr-onnxruntime' package. Would you like to install it now?"
                )

            import numpy as np
            with Image.open(file_path) as img:
                width, height = img.size
                if img.mode != "RGB":
                    img = img.convert("RGB")
                img_np = np.array(img)
                
                engine = RapidOCR()
                result, _ = engine(img_np)
                if result:
                    extracted_text = "\n".join([line[1] for line in result])
                else:
                    extracted_text = ""
        except DepsRequiredException:
            raise
        except Exception as e:
            logger.error(f"Failed to run OCR on {file_path}: {e}")
            raise RuntimeError(f"OCR processing failed: {e}")
            
        # Clean extracted text
        clean_text = extracted_text.strip()
        total_words = len(clean_text.split())
        total_chars = len(clean_text)
        
        # 2. Chunk text using boundary-aware splitter
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
                    child_chunks.append({
                        "index": child_idx,
                        "text": chunk_text,
                        "metadata": {
                            "image_dimensions": f"{width}x{height}",
                            "parent_id": parent_idx
                        }
                    })
                    child_idx += 1
                    
        # Save chunks to SQLite database
        from app.core.database import save_chunks_to_db
        save_chunks_to_db(workspace_id, source_id, parent_texts, child_chunks)
            
        # 4. Generate summary preview (first 300 characters of the document)
        summary = clean_text[:300].strip() + ("..." if total_chars > 300 else "")
        
        logger.info(f"Image processed: {width}x{height}, {total_words} words, {len(child_chunks)} child chunks, {len(parent_texts)} parent chunks generated.")
        return {
            "stats": {
                "width": width,
                "height": height,
                "words": total_words,
                "chunks": len(child_chunks)
            },
            "summary": summary
        }
