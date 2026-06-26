# app/core/processors/email.py
# Purpose: Email message content parsing and chunking pipeline.
# Responsibilities: Parses .eml files (from file uploads or pastes), extracts fields, chunks it, and saves chunks.

import json
import logging
from pathlib import Path
from typing import Dict, Any, List
from email import message_from_file

from app.core.config import settings
from app.core.processors.text import find_chunk_boundaries

logger = logging.getLogger("kivo.processors.email")

class EmailProcessor:
    def __init__(self, chunk_size: int = 1000, chunk_overlap: int = 200):
        self.chunk_size = chunk_size
        self.chunk_overlap = chunk_overlap

    def process(self, file_path: Path, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Parses raw email (EML) file, splits content into overlapping chunks,
        saves chunks to disk, and returns statistics and preview summary.
        """
        logger.info(f"Processing Email file: {file_path}")
        
        if not file_path.exists():
            raise FileNotFoundError(f"Email file not found at {file_path}")
            
        try:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                msg = message_from_file(f)
        except Exception as e:
            logger.error(f"Failed to parse email file at {file_path}: {e}")
            raise RuntimeError(f"Failed to parse email file: {e}")
            
        subject = msg.get("subject", "No Subject")
        sender = msg.get("from", "Unknown Sender")
        recipient = msg.get("to", "Unknown Recipient")
        
        # Extract plain text body
        body = ""
        try:
            if msg.is_multipart():
                for part in msg.walk():
                    content_type = part.get_content_type()
                    content_disposition = str(part.get("Content-Disposition"))
                    if content_type == "text/plain" and "attachment" not in content_disposition:
                        payload = part.get_payload(decode=True)
                        if payload:
                            body += payload.decode(errors="ignore")
            else:
                payload = msg.get_payload(decode=True)
                if payload:
                    body = payload.decode(errors="ignore")
        except Exception as e:
            logger.error(f"Failed to extract email body: {e}")
            
        body = body.strip()
        if not body:
            body = "[No body content found in email]"
            
        # Compose fully indexed content string including headers for rich semantic retrieval context
        formatted_content = f"Subject: {subject}\nFrom: {sender}\nTo: {recipient}\n\nBody:\n{body}"
        
        # Split text into overlapping chunks
        boundaries = find_chunk_boundaries(formatted_content, self.chunk_size, self.chunk_overlap)
        
        chunks = []
        for idx, (start, end) in enumerate(boundaries):
            chunk_text = formatted_content[start:end].strip()
            if chunk_text:
                chunks.append({
                    "index": idx,
                    "text": chunk_text,
                    "metadata": {
                        "source": "email",
                        "subject": subject,
                        "from": sender,
                        "to": recipient
                    }
                })
                
        # Save chunks to SQLite database
        from app.core.database import insert_chunks
        try:
            insert_chunks(workspace_id, source_id, chunks)
        except Exception as e:
            logger.error(f"Failed to insert email chunks into SQLite database: {e}")
            raise RuntimeError(f"Failed to index email chunks: {e}")
            
        # Generate short summary preview
        preview_body = body[:200] + "..." if len(body) > 200 else body
        summary = f"Email from {sender} to {recipient} regarding '{subject}'.\nPreview:\n{preview_body}"
        
        word_count = len(formatted_content.split())
        
        return {
            "stats": {
                "pages": 1,  # Email is treated as a single page document
                "words": word_count,
                "chunks": len(chunks)
            },
            "summary": summary
        }
