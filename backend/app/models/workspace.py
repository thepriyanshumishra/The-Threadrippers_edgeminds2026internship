# app/models/workspace.py
# Purpose: Pydantic schemas for Workspace CRUD operations.
# Responsibilities: Defines validation models for HTTP requests/responses.

from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class WorkspaceBase(BaseModel):
    name: str = Field(..., description="The name of the workspace", min_length=1, max_length=100)
    instructions: Optional[str] = Field("", description="Custom workspace system instructions")

class WorkspaceCreate(WorkspaceBase):
    pass

class WorkspaceRename(WorkspaceBase):
    pass

class WorkspaceUpdate(BaseModel):
    name: Optional[str] = Field(None, description="The name of the workspace", min_length=1, max_length=100)
    instructions: Optional[str] = Field(None, description="Custom workspace system instructions")

class Workspace(WorkspaceBase):
    id: str = Field(..., pattern=r"^[0-9a-f-]{36}$", description="Unique workspace identifier")
    created_at: datetime = Field(..., description="Timestamp when workspace was created")
    status: str = Field("ready", description="Status of workspace processing (ready, processing, failed)")
    sources_count: int = Field(0, description="Total number of sources added to the workspace")

    class Config:
        json_schema_extra = {
            "example": {
                "id": "e4f8d223-9f8e-4a6c-905c-e6593539a2f1",
                "name": "My Research Workspace",
                "created_at": "2026-06-16T22:00:00.000Z",
                "status": "ready",
                "sources_count": 2
            }
        }
