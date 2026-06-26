# app/api/routes/workspaces.py
# Purpose: APIRouter for workspace CRUD operations.
# Responsibilities: Implements list, get, create, rename, delete workspaces on local disk.

from fastapi import APIRouter, HTTPException, Path, Body
import shutil
import json
import uuid
import logging
from datetime import datetime, timezone
from typing import List

from app.core.config import settings
from app.models.workspace import Workspace, WorkspaceCreate, WorkspaceRename, WorkspaceUpdate

logger = logging.getLogger("kivo.workspaces")
router = APIRouter()

def get_workspace_dir(workspace_id: str):
    return settings.workspaces_dir / workspace_id

def get_metadata_path(workspace_id: str):
    return get_workspace_dir(workspace_id) / "metadata.json"

@router.get("", response_model=List[Workspace])
def list_workspaces():
    """List all available workspaces by reading workspace folders."""
    workspaces = []
    if not settings.workspaces_dir.exists():
        return workspaces
        
    for item in settings.workspaces_dir.iterdir():
        if item.is_dir():
            metadata_file = item / "metadata.json"
            if metadata_file.exists():
                try:
                    with open(metadata_file, "r") as f:
                        data = json.load(f)
                    workspaces.append(Workspace(**data))
                except Exception as e:
                    logger.error(f"Failed to read workspace metadata in {item}: {e}")
                    # Skip corrupt workspace directory
                    pass
                    
    # Sort by created_at descending (newest first)
    workspaces.sort(key=lambda x: x.created_at, reverse=True)
    return workspaces

@router.post("", response_model=Workspace)
def create_workspace(payload: WorkspaceCreate):
    """Create a new workspace directory and initialize its metadata.json."""
    workspace_id = str(uuid.uuid4())
    workspace_dir = get_workspace_dir(workspace_id)
    workspace_dir.mkdir(parents=True, exist_ok=True)
    
    # We use UTC timestamp with timezone formatting or naive UTC.
    # ISO-8601 parsing handles it well.
    metadata = Workspace(
        id=workspace_id,
        name=payload.name,
        created_at=datetime.now(timezone.utc),
        status="ready",
        sources_count=0
    )
    
    metadata_file = get_metadata_path(workspace_id)
    try:
        with open(metadata_file, "w") as f:
            f.write(metadata.model_dump_json())
    except Exception as e:
        logger.error(f"Failed to write metadata for new workspace {workspace_id}: {e}")
        # Clean up directory on failure
        shutil.rmtree(workspace_dir, ignore_errors=True)
        raise HTTPException(status_code=500, detail="Failed to create workspace storage")
        
    logger.info(f"Workspace '{payload.name}' created with ID {workspace_id}")
    return metadata

@router.get("/{workspace_id}", response_model=Workspace)
def get_workspace(workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID")):
    """Get metadata details of a specific workspace."""
    metadata_file = get_metadata_path(workspace_id)
    if not metadata_file.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    try:
        with open(metadata_file, "r") as f:
            data = json.load(f)
        return Workspace(**data)
    except Exception as e:
        logger.error(f"Failed to load workspace metadata for {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to read workspace metadata")

@router.put("/{workspace_id}", response_model=Workspace)
def update_workspace(
    workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID"),
    payload: WorkspaceUpdate = Body(...)
):
    """Update an existing workspace's metadata (rename name or update instructions)."""
    metadata_file = get_metadata_path(workspace_id)
    if not metadata_file.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    try:
        with open(metadata_file, "r") as f:
            data = json.load(f)
        
        workspace = Workspace(**data)
        if payload.name is not None:
            workspace.name = payload.name
        if payload.instructions is not None:
            workspace.instructions = payload.instructions
        
        with open(metadata_file, "w") as f:
            f.write(workspace.model_dump_json())
            
        logger.info(f"Workspace {workspace_id} updated. Name: {workspace.name}, Instructions: {workspace.instructions}")
        return workspace
    except Exception as e:
        logger.error(f"Failed to update workspace {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to update workspace metadata")

@router.delete("/{workspace_id}")
def delete_workspace(workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID")):
    """Delete a workspace and all of its associated files."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    # Cancel any active background processing job for this workspace
    try:
        from app.api.routes.processing import processing_jobs
        if workspace_id in processing_jobs:
            job = processing_jobs[workspace_id]
            if "cancel_event" in job:
                job["cancel_event"].set()
                logger.info(f"Cancelled active processing job for deleted workspace {workspace_id}")
            processing_jobs.pop(workspace_id, None)
    except Exception as e:
        logger.error(f"Error cancelling active processing job for workspace {workspace_id}: {e}")

    try:
        shutil.rmtree(workspace_dir)
        logger.info(f"Workspace {workspace_id} deleted successfully.")
        return {"status": "ok", "message": f"Workspace {workspace_id} deleted successfully"}
    except Exception as e:
        logger.error(f"Failed to delete workspace directory {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to delete workspace storage")


@router.get("/{workspace_id}/stats")
def get_workspace_stats(workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID")):
    """Get statistics for the workspace (chunk count, embedding dimension, etc.)."""
    metadata_file = get_metadata_path(workspace_id)
    if not metadata_file.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    # Count chunks from SQLite
    import sqlite3
    chunks_count = 0
    db_path = get_workspace_dir(workspace_id) / "metadata.db"
    if db_path.exists():
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM child_chunks")
            chunks_count = cursor.fetchone()[0]
            conn.close()
        except Exception as e:
            logger.error(f"Failed to query child_chunks count for workspace {workspace_id}: {e}")
            
    return {
        "chunks_count": chunks_count,
        "embedding_dim": 768,
        "embedding_model": "gte-multilingual-base",
        "llm_model": settings.ollama_default_model,
        "status": "ready"
    }

