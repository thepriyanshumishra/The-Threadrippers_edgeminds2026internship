# app/models/source.py
# Purpose: Pydantic schemas for Source management.
# Responsibilities: Defines validation models for Source metadata and requests.

from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class SourceBase(BaseModel):
    name: str = Field(..., description="Name of the source file, video title, or website title")
    type: str = Field(..., description="Type of source (pdf, image, audio, youtube, website, text, email)")

class YouTubeCreate(BaseModel):
    url: str = Field(..., description="YouTube video URL")

class WebsiteCreate(BaseModel):
    url: str = Field(..., description="Website page URL")

class TextCreate(BaseModel):
    name: str = Field(..., description="Name for the copied text source")
    content: str = Field(..., description="Raw text content to ingest")

class EmailCreate(BaseModel):
    subject: str = Field(..., description="Subject of the email")
    sender: str = Field(..., description="Sender/From of the email")
    recipient: str = Field(..., description="Recipient/To of the email")
    body: str = Field(..., description="Body text content of the email")

class Source(SourceBase):
    id: str = Field(..., description="Unique source identifier")
    path: Optional[str] = Field(None, description="Relative path of saved file on disk")
    url: Optional[str] = Field(None, description="YouTube link if type is youtube")
    added_at: datetime = Field(..., description="Timestamp when source was attached")
    size_bytes: Optional[int] = Field(None, description="Size of file in bytes")
    status: str = Field("pending", description="Processing status (pending, processing, ready, failed)")
    summary: Optional[str] = Field(None, description="Extracted textual summary or preview")
    stats: Optional[dict] = Field(None, description="Extracted statistics (pages, words, chunks)")

    class Config:
        json_schema_extra = {
            "example": {
                "id": "s7f8d223-9f8e-4a6c-905c-e6593539a2f1",
                "name": "annual_report.pdf",
                "type": "pdf",
                "path": "storage/workspaces/e4f8d223/sources/annual_report.pdf",
                "url": None,
                "added_at": "2026-06-16T22:15:00.000Z",
                "size_bytes": 1048576,
                "status": "pending"
            }
        }
