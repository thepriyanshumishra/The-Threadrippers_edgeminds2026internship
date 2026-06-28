# app/api/routes/processing.py
# Purpose: APIRouter for sequential background ingestion pipelines.
# Responsibilities: Triggers progress, gets current execution state, and allows cancellation.

from fastapi import APIRouter, HTTPException, Path
import threading
import time
import json
import logging
from typing import Dict, Any, List, Optional
from pathlib import Path as FilePath


from app.core.config import settings
from app.models.processing import ProcessingStatusResponse
from app.api.routes.workspaces import get_workspace_dir, get_metadata_path
from app.api.routes.sources import load_sources, save_sources
from app.models.workspace import Workspace
from app.core.database import init_db
from app.core.exceptions import DepsRequiredException

logger = logging.getLogger("kivo.processing")
router = APIRouter()

# In-memory database of active processing jobs
# workspace_id -> Dict
processing_jobs: Dict[str, Dict[str, Any]] = {}

def _resolve_source_path(relative_path: str) -> FilePath:
    if not relative_path:
        return None
    p = FilePath(relative_path)
    if p.is_absolute():
        return p
    return settings.storage_dir.parent / p

def _update_sources_status_by_step(sources: list, step: str, status: str):
    for src in sources:
        if step == "pdf_extraction" and src.type == "pdf":
            src.status = status
        elif step == "image_ocr" and src.type == "image":
            src.status = status
        elif step == "audio_transcription" and src.type == "audio":
            src.status = status
        elif step == "youtube_transcription" and src.type == "youtube":
            src.status = status
        elif step == "website_extraction" and src.type == "website":
            src.status = status
        elif step == "text_extraction" and src.type == "text":
            src.status = status
        elif step in ["embedding_generation", "building_knowledge_base"]:
            # These apply to all sources
            src.status = status

def _update_workspace_status(workspace_id: str, status: str):
    metadata_file = get_metadata_path(workspace_id)
    if not metadata_file.exists():
        return
    try:
        with open(metadata_file, "r") as f:
            data = json.load(f)
        workspace = Workspace(**data)
        workspace.status = status
        with open(metadata_file, "w") as f:
            f.write(workspace.model_dump_json())
    except Exception as e:
        logger.error(f"Failed to update workspace status for {workspace_id} to {status}: {e}")

def _mark_source_failed(job: dict, src: Any):
    src.status = "failed"
    name = src.name or src.path or src.url or "Unknown Source"
    if "failed_sources" not in job:
        job["failed_sources"] = []
    if name not in job["failed_sources"]:
        job["failed_sources"].append(name)

def run_processing_pipeline(workspace_id: str, steps: List[str], cancel_event: threading.Event, chunk_size: int = 1000, chunk_overlap: int = 200):
    logger.info(f"Background processing thread started for workspace {workspace_id}")
    job = processing_jobs.get(workspace_id)
    if not job:
        return
    if "failed_sources" not in job:
        job["failed_sources"] = []
        
    try:
        init_db(workspace_id)
        sources = load_sources(workspace_id)
        
        for idx, step in enumerate(steps):
            if cancel_event.is_set():
                logger.info(f"Cancellation requested. Stopping thread for {workspace_id}")
                return
                
            # Update job state
            job["current_step"] = step
            job["progress"] = idx / len(steps)
            
            # Update source statuses to 'processing'
            _update_sources_status_by_step(sources, step, "processing")
            save_sources(workspace_id, sources)
            
            if step == "pdf_extraction":
                try:
                    from app.core.processors.pdf import PDFProcessor
                except ImportError:
                    raise DepsRequiredException(
                        ["pymupdf"],
                        message="PDF text extraction requires the PyMuPDF ('pymupdf') package. Would you like to install it now?"
                    )
                processor = PDFProcessor(chunk_size=chunk_size, chunk_overlap=chunk_overlap)
                for src in sources:
                    if src.type == "pdf" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during PDF processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            file_path = _resolve_source_path(src.path)
                            if file_path and file_path.exists():
                                res = processor.process(file_path, workspace_id, src.id)
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                            else:
                                logger.error(f"PDF source file {src.name} not found at path: {file_path}")
                                _mark_source_failed(job, src)
                        except DepsRequiredException as e:
                            logger.error(f"Failed to process PDF source {src.id} due to missing dependencies: {e}")
                            _mark_source_failed(job, src)
                            save_sources(workspace_id, sources)
                            raise
                        except Exception as e:
                            logger.error(f"Failed to process PDF source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "image_ocr":
                try:
                    from app.core.processors.image import ImageProcessor
                except ImportError:
                    raise DepsRequiredException(
                        ["rapidocr-onnxruntime"],
                        message="Image OCR processing requires the 'rapidocr-onnxruntime' package. Would you like to install it now?"
                    )
                processor = ImageProcessor()
                for src in sources:
                    if src.type == "image" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Image processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            file_path = _resolve_source_path(src.path)
                            if file_path and file_path.exists():
                                res = processor.process(file_path, workspace_id, src.id)
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                            else:
                                logger.error(f"Image source file {src.name} not found at path: {file_path}")
                                _mark_source_failed(job, src)
                        except DepsRequiredException as e:
                            logger.error(f"Failed to process Image source {src.id} due to missing dependencies: {e}")
                            _mark_source_failed(job, src)
                            save_sources(workspace_id, sources)
                            raise
                        except Exception as e:
                            logger.error(f"Failed to process Image source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "audio_transcription":
                try:
                    from app.core.processors.audio import AudioProcessor
                except ImportError:
                    raise DepsRequiredException(
                        ["faster-whisper"],
                        message="Audio transcription requires the 'faster-whisper' package. Would you like to install it now?"
                    )
                processor = AudioProcessor()
                for src in sources:
                    if src.type == "audio" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Audio processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            file_path = _resolve_source_path(src.path)
                            if file_path and file_path.exists():
                                res = processor.process(file_path, workspace_id, src.id)
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                            else:
                                logger.error(f"Audio source file {src.name} not found at path: {file_path}")
                                _mark_source_failed(job, src)
                        except DepsRequiredException as e:
                            logger.error(f"Failed to process Audio source {src.id} due to missing dependencies: {e}")
                            _mark_source_failed(job, src)
                            save_sources(workspace_id, sources)
                            raise
                        except Exception as e:
                            logger.error(f"Failed to process Audio source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "youtube_transcription":
                try:
                    from app.core.processors.audio import AudioProcessor
                    from app.core.processors.youtube import YouTubeProcessor
                except ImportError:
                    raise DepsRequiredException(
                        ["yt-dlp", "faster-whisper"],
                        message="YouTube video processing requires 'yt-dlp' and 'faster-whisper' packages. Would you like to install them now?"
                    )
                audio_processor = AudioProcessor()
                youtube_processor = YouTubeProcessor(audio_processor)
                sources_dir = get_workspace_dir(workspace_id) / "sources"
                for src in sources:
                    if src.type == "youtube" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during YouTube processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            if src.url:
                                res = youtube_processor.process(src.url, workspace_id, src.id, sources_dir)
                                src.name = res["title"]
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                        except DepsRequiredException as e:
                            logger.error(f"Failed to process YouTube source {src.id} due to missing dependencies: {e}")
                            _mark_source_failed(job, src)
                            save_sources(workspace_id, sources)
                            raise
                        except Exception as e:
                            logger.error(f"Failed to process YouTube source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "website_extraction":
                try:
                    from app.core.processors.website import WebsiteProcessor
                except ImportError:
                    raise DepsRequiredException(
                        ["beautifulsoup4", "readability-lxml", "playwright"],
                        message="Website extraction requires 'beautifulsoup4', 'readability-lxml', and 'playwright'. Would you like to install them now?"
                    )
                processor = WebsiteProcessor(chunk_size=chunk_size, chunk_overlap=chunk_overlap)
                for src in sources:
                    if src.type == "website" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Website processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            if src.url:
                                res = processor.process(src.url, workspace_id, src.id)
                                src.name = res["title"]
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                        except DepsRequiredException as e:
                            logger.error(f"Failed to process Website source {src.id} due to missing dependencies: {e}")
                            _mark_source_failed(job, src)
                            save_sources(workspace_id, sources)
                            raise
                        except Exception as e:
                            logger.error(f"Failed to process Website source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "text_extraction":
                from app.core.processors.text import TextProcessor
                processor = TextProcessor(chunk_size=chunk_size, chunk_overlap=chunk_overlap)
                for src in sources:
                    if src.type == "text" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Text processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            file_path = _resolve_source_path(src.path)
                            if file_path and file_path.exists():
                                res = processor.process(file_path, workspace_id, src.id)
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                            else:
                                logger.error(f"Text source file {src.name} not found at path: {file_path}")
                                _mark_source_failed(job, src)
                        except Exception as e:
                            logger.error(f"Failed to process Text source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "email_extraction":
                from app.core.processors.email import EmailProcessor
                processor = EmailProcessor(chunk_size=chunk_size, chunk_overlap=chunk_overlap)
                for src in sources:
                    if src.type == "email" and src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Email processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            file_path = _resolve_source_path(src.path)
                            if file_path and file_path.exists():
                                res = processor.process(file_path, workspace_id, src.id)
                                src.stats = res["stats"]
                                src.summary = res["summary"]
                            else:
                                logger.error(f"Email source file {src.name} not found at path: {file_path}")
                                _mark_source_failed(job, src)
                        except Exception as e:
                            logger.error(f"Failed to process Email source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "embedding_generation":
                from app.core.processors.embeddings import EmbeddingProcessor
                processor = EmbeddingProcessor()
                for src in sources:
                    if src.status == "processing":
                        if cancel_event.is_set():
                            logger.info(f"Cancellation requested during Embedding processing. Stopping thread for {workspace_id}")
                            return
                        try:
                            # Generate embeddings for this source (processes chunks JSON)
                            res = processor.process(workspace_id, src.id)
                            # Update stats if embedding processor successfully processed
                            if "chunks_count" in res and src.stats:
                                src.stats["chunks"] = res["chunks_count"]
                        except Exception as e:
                            logger.error(f"Failed to generate embeddings for source {src.id}: {e}")
                            _mark_source_failed(job, src)
            elif step == "building_knowledge_base":
                from app.core.processors.vector_db import VectorDBProcessor
                processor = VectorDBProcessor()
                if cancel_event.is_set():
                    logger.info(f"Cancellation requested during Knowledge Base building. Stopping thread for {workspace_id}")
                    return
                try:
                    # Compile vectors and build the workspace FAISS index
                    processor.process(workspace_id)
                except Exception as e:
                    logger.error(f"Failed to build vector index for workspace {workspace_id}: {e}")
                    raise RuntimeError(f"Failed to build knowledge base: {e}")
            else:
                step_duration = 3.0
                poll_interval = 0.2
                elapsed = 0.0
                while elapsed < step_duration:
                    if cancel_event.is_set():
                        logger.info(f"Cancellation requested during sleep. Stopping thread for {workspace_id}")
                        return
                    time.sleep(poll_interval)
                    elapsed += poll_interval
                
            # Mark sources ready for this step
            _update_sources_status_by_step(sources, step, "ready")
            save_sources(workspace_id, sources)
            job["completed_steps"].append(step)
            
        # Complete all steps
        job["status"] = "ready"
        job["progress"] = 1.0
        job["current_step"] = None
        
        # Ensure all successful/processing sources are ready
        for src in sources:
            if src.status != "failed":
                src.status = "ready"
        save_sources(workspace_id, sources)
        
        # Set workspace metadata status to ready
        _update_workspace_status(workspace_id, "ready")
        logger.info(f"Background processing pipeline completed for workspace {workspace_id}")
        
        # Trigger macOS OS notification
        try:
            import platform
            import subprocess
            if platform.system() == "Darwin":
                metadata_file = get_metadata_path(workspace_id)
                workspace_name = "Workspace"
                if metadata_file.exists():
                    try:
                        with open(metadata_file, "r") as f:
                            data = json.load(f)
                        workspace_name = data.get("name", "Workspace")
                    except Exception:
                        pass
                subprocess.run([
                    "osascript", "-e",
                    f'display notification "Ingestion completed successfully for workspace \'{workspace_name}\'." with title "Kivo Workspace" subtitle "Processing Complete" sound name "Glass"'
                ])
        except Exception as notify_err:
            logger.error(f"Failed to send OS notification: {notify_err}")
        
    except DepsRequiredException as e:
        logger.error(f"Pipeline failure in workspace {workspace_id} due to missing dependencies: {e}")
        job["status"] = "failed"
        job["error_type"] = "deps_required"
        job["missing_packages"] = e.deps
        _update_workspace_status(workspace_id, "failed")
    except Exception as e:
        logger.error(f"Pipeline failure in workspace {workspace_id}: {e}")
        job["status"] = "failed"
        _update_workspace_status(workspace_id, "failed")


@router.post("/process", response_model=ProcessingStatusResponse)
def start_processing(
    workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID"),
    chunk_size: Optional[int] = None,
    chunk_overlap: Optional[int] = None
):
    """Trigger background sequential extraction and processing pipeline."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    # Check if there is already an active job running
    active_job = processing_jobs.get(workspace_id)
    if active_job and active_job["status"] == "processing":
        return ProcessingStatusResponse(**active_job)
        
    # Get list of sources to determine which steps are required
    sources = load_sources(workspace_id)
    if not sources:
        raise HTTPException(status_code=400, detail="Cannot process workspace with 0 sources")
        
    # Determine steps based on source types
    steps = []
    has_pdf = any(s.type == "pdf" for s in sources)
    has_image = any(s.type == "image" for s in sources)
    has_audio = any(s.type == "audio" for s in sources)
    has_youtube = any(s.type == "youtube" for s in sources)
    has_website = any(s.type == "website" for s in sources)
    has_text = any(s.type == "text" for s in sources)
    has_email = any(s.type == "email" for s in sources)
    
    if has_pdf:
        steps.append("pdf_extraction")
    if has_image:
        steps.append("image_ocr")
    if has_audio:
        steps.append("audio_transcription")
    if has_youtube:
        steps.append("youtube_transcription")
    if has_website:
        steps.append("website_extraction")
    if has_text:
        steps.append("text_extraction")
    if has_email:
        steps.append("email_extraction")
        
    # Always include embeddings and base indexing steps
    steps.extend(["embedding_generation", "building_knowledge_base"])
    
    # Initialize workspace status in metadata.json to processing
    _update_workspace_status(workspace_id, "processing")
    
    # Create thread cancellation flag
    cancel_event = threading.Event()
    
    # Initialize job state
    job = {
        "status": "processing",
        "current_step": steps[0],
        "progress": 0.0,
        "steps": steps,
        "completed_steps": [],
        "cancel_event": cancel_event
    }
    processing_jobs[workspace_id] = job
    
    c_size = chunk_size if chunk_size is not None else settings.chunk_size
    c_overlap = chunk_overlap if chunk_overlap is not None else settings.chunk_overlap

    # Start thread
    thread = threading.Thread(
        target=run_processing_pipeline,
        args=(workspace_id, steps, cancel_event, c_size, c_overlap),
        daemon=True
    )
    thread.start()
    
    return ProcessingStatusResponse(
        status=job["status"],
        current_step=job["current_step"],
        progress=job["progress"],
        steps=job["steps"],
        completed_steps=job["completed_steps"],
        failed_sources=job.get("failed_sources")
    )

@router.get("/processing-status", response_model=ProcessingStatusResponse)
def get_processing_status(workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID")):
    """Get current progress status of the processing pipeline."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    job = processing_jobs.get(workspace_id)
    if not job:
        # Check workspace status from file metadata as fallback
        metadata_file = get_metadata_path(workspace_id)
        ws_status = "ready"
        if metadata_file.exists():
            try:
                with open(metadata_file, "r") as f:
                    data = json.load(f)
                ws_status = data.get("status", "ready")
            except Exception:
                pass
        
        # Check if there are any failed sources
        failed_sources = []
        try:
            sources = load_sources(workspace_id)
            for s in sources:
                if s.status == "failed":
                    failed_sources.append(s.name or s.path or s.url or "Unknown Source")
        except Exception:
            pass
            
        return ProcessingStatusResponse(
            status=ws_status,
            current_step=None,
            progress=1.0 if ws_status == "ready" else 0.0,
            steps=[],
            completed_steps=[],
            failed_sources=failed_sources if failed_sources else None
        )
        
    return ProcessingStatusResponse(
        status=job["status"],
        current_step=job["current_step"],
        progress=job["progress"],
        steps=job["steps"],
        completed_steps=job["completed_steps"],
        error_type=job.get("error_type"),
        missing_packages=job.get("missing_packages"),
        failed_sources=job.get("failed_sources")
    )

@router.post("/cancel-processing")
def cancel_processing(workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The unique workspace ID")):
    """Cancel active processing queue."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
        
    job = processing_jobs.get(workspace_id)
    if not job or job["status"] != "processing":
        raise HTTPException(status_code=400, detail="No active processing job to cancel")
        
    # Trigger cancel event
    cancel_event = job["cancel_event"]
    cancel_event.set()
    
    # Update state
    job["status"] = "cancelled"
    job["current_step"] = None
    
    # Update workspace metadata to ready or cancelled (let's set to ready, so it's usable but empty)
    _update_workspace_status(workspace_id, "ready")
    
    # Reset all pending sources status back to pending
    try:
        sources = load_sources(workspace_id)
        for s in sources:
            if s.status in ["pending", "processing"]:
                s.status = "pending"
        save_sources(workspace_id, sources)
    except Exception:
        pass
        
    logger.info(f"Processing cancelled for workspace {workspace_id}")
    return {"status": "ok", "message": "Processing cancelled"}
