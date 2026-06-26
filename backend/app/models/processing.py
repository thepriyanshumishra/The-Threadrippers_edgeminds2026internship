# app/models/processing.py
# Purpose: Pydantic schemas for workspace ingestion processing status.
# Responsibilities: Defines response models for progress updates.

from pydantic import BaseModel, Field
from typing import List, Optional

class ProcessingStatusResponse(BaseModel):
    status: str = Field(..., description="Overall processing status (ready, processing, failed, cancelled)")
    current_step: Optional[str] = Field(None, description="The key name of the step currently executing")
    progress: float = Field(0.0, description="Overall progress percentage as a fraction (0.0 to 1.0)")
    steps: List[str] = Field(default_factory=list, description="Ordered list of steps to execute")
    completed_steps: List[str] = Field(default_factory=list, description="List of steps already finished")

    class Config:
        json_schema_extra = {
            "example": {
                "status": "processing",
                "current_step": "pdf_extraction",
                "progress": 0.33,
                "steps": ["pdf_extraction", "embedding_generation", "building_knowledge_base"],
                "completed_steps": []
            }
        }
