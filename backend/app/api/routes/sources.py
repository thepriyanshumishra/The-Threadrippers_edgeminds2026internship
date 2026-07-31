# app/api/routes/sources.py
# Purpose: APIRouter for workspace sources.
# Responsibilities: Handles file uploads, YouTube URL registration, source listing, and deletion.

from fastapi import APIRouter, HTTPException, Path, UploadFile, File, Body
import shutil
import json
import uuid
import logging
import re
from datetime import datetime, timezone
from pathlib import Path as FilePath
from typing import List

from urllib.parse import urlparse
from app.core.config import settings
from app.models.source import (
    Source,
    YouTubeCreate,
    WebsiteCreate,
    TextCreate,
    EmailCreate,
)
from app.api.routes.workspaces import get_workspace_dir, get_metadata_path
from app.models.workspace import Workspace

logger = logging.getLogger("kivo.sources")
router = APIRouter()

def safe_file_path(workspace_dir: FilePath, filename: str) -> FilePath:
    """Ensure the file path stays within the workspace directory."""
    # Strip any path components from filename
    safe_name = FilePath(filename).name  # gets just the filename, no directory parts
    target = (workspace_dir / safe_name).resolve()
    # Verify it's still inside the workspace directory
    if not str(target).startswith(str(workspace_dir.resolve())):
        raise ValueError(f"Path traversal detected: {filename}")
    return target



def get_sources_json_path(workspace_id: str):
    return get_workspace_dir(workspace_id) / "sources.json"


def get_sources_upload_dir(workspace_id: str):
    return get_workspace_dir(workspace_id) / "sources"


def load_sources(workspace_id: str) -> List[Source]:
    sources_file = get_sources_json_path(workspace_id)
    if not sources_file.exists():
        return []
    try:
        with open(sources_file, "r") as f:
            data = json.load(f)
        return [Source(**item) for item in data]
    except Exception as e:
        logger.error(f"Failed to load sources from {sources_file}: {e}")
        return []


def save_sources(workspace_id: str, sources: List[Source]):
    sources_file = get_sources_json_path(workspace_id)
    if not sources_file.parent.exists():
        logger.warning(
            f"Workspace directory {sources_file.parent} does not exist. Skipping save_sources."
        )
        return
    try:
        with open(sources_file, "w") as f:
            # Serialize each pydantic model in the list
            json_data = [json.loads(s.model_dump_json()) for s in sources]
            json.dump(json_data, f, indent=2)
        # Clear the RAG cache
        try:
            from app.core.retriever import invalidate_workspace_cache

            invalidate_workspace_cache(workspace_id)
        except Exception as cache_err:
            logger.error(f"Failed to clear RAG cache: {cache_err}")
    except Exception as e:
        logger.error(f"Failed to save sources to {sources_file}: {e}")
        raise HTTPException(status_code=500, detail="Failed to save source registry")


def update_workspace_sources_count(workspace_id: str, count: int):
    metadata_file = get_metadata_path(workspace_id)
    if not metadata_file.exists():
        return
    try:
        with open(metadata_file, "r") as f:
            data = json.load(f)
        workspace = Workspace(**data)
        workspace.sources_count = count
        with open(metadata_file, "w") as f:
            f.write(workspace.model_dump_json())
    except Exception as e:
        logger.error(
            f"Failed to update workspace sources count for {workspace_id}: {e}"
        )


@router.get("", response_model=List[Source])
def list_sources(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    )
):
    """List all sources attached to the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")
    return load_sources(workspace_id)


@router.post("/upload", response_model=List[Source])
async def upload_sources(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    files: List[UploadFile] = File(...),
):
    """Upload one or more files (PDF, Image, Audio) to the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    upload_dir = get_sources_upload_dir(workspace_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    current_sources = load_sources(workspace_id)
    new_sources = []

    for file in files:
        if not file.filename:
            continue

        ALLOWED_EXTENSIONS = {
            ".pdf",
            ".txt",
            ".md",
            ".mp3",
            ".wav",
            ".m4a",
            ".ogg",
            ".jpg",
            ".jpeg",
            ".png",
            ".gif",
            ".webp",
        }
        from pathlib import Path

        file_ext = Path(file.filename or "").suffix.lower()
        if file_ext not in ALLOWED_EXTENSIONS:
            raise HTTPException(
                status_code=400, detail=f"File type '{file_ext}' is not supported"
            )

        # Detect type from extension
        ext = file_ext
        if ext == ".pdf":
            source_type = "pdf"
        elif ext in [".png", ".jpg", ".jpeg", ".webp", ".gif"]:
            source_type = "image"
        elif ext in [".mp3", ".wav", ".m4a", ".ogg"]:
            source_type = "audio"
        elif ext in [".txt", ".md"]:
            source_type = "text"
        else:
            raise HTTPException(
                status_code=400, detail=f"Unsupported file format for {file.filename}"
            )

        # Create safe unique file path on disk
        source_id = str(uuid.uuid4())
        filename = f"{source_id}_{FilePath(file.filename).name}"
        try:
            dest_path = safe_file_path(upload_dir, filename)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

        # Read bytes asynchronously from request stream to avoid event-loop blocking
        MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB
        try:
            content = await file.read()
            with open(dest_path, "wb") as buffer:
                buffer.write(content)
        except Exception as e:
            logger.error(f"Failed to write file {filename} to disk: {e}")
            raise HTTPException(
                status_code=500, detail=f"Failed to save file {file.filename}"
            )

        # Verify file size
        size_bytes = dest_path.stat().st_size
        if size_bytes == 0:
            dest_path.unlink(missing_ok=True)
            raise HTTPException(status_code=400, detail="Uploaded file is empty")
        if size_bytes > MAX_FILE_SIZE:
            dest_path.unlink(missing_ok=True)
            raise HTTPException(
                status_code=413, detail="File too large. Max size is 100MB"
            )

        # Create Source metadata
        src = Source(
            id=source_id,
            name=file.filename,
            type=source_type,
            path=str(dest_path.relative_to(settings.storage_dir.parent)),
            url=None,
            added_at=datetime.now(timezone.utc),
            size_bytes=size_bytes,
            status="pending",
        )
        new_sources.append(src)

    current_sources.extend(new_sources)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Uploaded {len(new_sources)} files to workspace {workspace_id}")
    return new_sources


def get_youtube_title(url: str, video_id: str) -> str:
    try:
        import httpx

        oembed_url = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={video_id}&format=json"
        response = httpx.get(oembed_url, timeout=3)
        if response.status_code == 200:
            data = response.json()
            title = data.get("title")
            if title:
                return f"YouTube: {title}"
    except Exception as e:
        logger.warning(f"Failed to fetch YouTube title for {video_id}: {e}")
    return f"YouTube: {video_id}"


def get_website_title(url: str, default_domain: str) -> str:
    try:
        import httpx
        from bs4 import BeautifulSoup

        headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        response = httpx.get(url, headers=headers, timeout=3.0)
        if response.status_code == 200:
            soup = BeautifulSoup(response.text, "html.parser")
            if soup.title and soup.title.string:
                title = soup.title.string.strip()
                if title:
                    return f"Website: {title}"
    except Exception as e:
        logger.warning(f"Failed to fetch website title for {url}: {e}")
    return f"Website: {default_domain}"


@router.post("/youtube", response_model=Source)
def add_youtube_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    payload: YouTubeCreate = Body(...),
):
    """Add a YouTube URL as a source for the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    # Validate YouTube URL pattern
    url = payload.url.strip()
    youtube_pattern = re.compile(
        r"(https?://)?(www\.)?(youtube|youtu|youtube-nocookie)\.(com|be)/(watch\?v=|embed/|v/|.+\?v=)?([^&=%\?]{11})"
    )
    match = youtube_pattern.match(url)
    if not match:
        raise HTTPException(status_code=400, detail="Invalid YouTube video URL")

    video_id = match.group(6)

    current_sources = load_sources(workspace_id)

    # Check if this URL is already added
    for src in current_sources:
        if src.type == "youtube" and src.url == url:
            raise HTTPException(
                status_code=400,
                detail="YouTube URL already registered in this workspace",
            )

    source_id = str(uuid.uuid4())
    video_title = get_youtube_title(url, video_id)

    src = Source(
        id=source_id,
        name=video_title,
        type="youtube",
        path=None,
        url=url,
        added_at=datetime.now(timezone.utc),
        size_bytes=None,
        status="pending",
    )

    current_sources.append(src)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Registered YouTube video {video_id} in workspace {workspace_id}")
    return src


@router.post("/website", response_model=Source)
def add_website_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    payload: WebsiteCreate = Body(...),
):
    """Add a website URL as a source for the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    url = payload.url.strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        raise HTTPException(
            status_code=400,
            detail="Invalid website URL. Must start with http:// or https://",
        )

    current_sources = load_sources(workspace_id)

    # Check if URL already exists
    for src in current_sources:
        if src.type == "website" and src.url == url:
            raise HTTPException(
                status_code=400,
                detail="Website URL already registered in this workspace",
            )

    parsed_url = urlparse(url)
    domain = parsed_url.netloc or parsed_url.path
    if not domain:
        domain = "Unknown Website"

    source_id = str(uuid.uuid4())
    web_title = get_website_title(url, domain)

    src = Source(
        id=source_id,
        name=web_title,
        type="website",
        path=None,
        url=url,
        added_at=datetime.now(timezone.utc),
        size_bytes=None,
        status="pending",
    )

    current_sources.append(src)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Registered website {domain} in workspace {workspace_id}")
    return src


@router.post("/text", response_model=Source)
def add_text_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    payload: TextCreate = Body(...),
):
    """Add pasted text as a source for the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    name = payload.name.strip()
    if not name:
        name = "Pasted Text"

    # Standardize name extension if not present
    if not name.endswith(".txt"):
        name = f"{name}.txt"

    upload_dir = get_sources_upload_dir(workspace_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    source_id = str(uuid.uuid4())
    filename = f"{source_id}_text.txt"
    try:
        dest_path = safe_file_path(upload_dir, filename)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    try:
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(payload.content)
    except Exception as e:
        logger.error(f"Failed to write text file {filename} to disk: {e}")
        raise HTTPException(status_code=500, detail="Failed to save copied text source")

    size_bytes = dest_path.stat().st_size

    current_sources = load_sources(workspace_id)
    src = Source(
        id=source_id,
        name=name,
        type="text",
        path=str(dest_path.relative_to(settings.storage_dir.parent)),
        url=None,
        added_at=datetime.now(timezone.utc),
        size_bytes=size_bytes,
        status="pending",
    )

    current_sources.append(src)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Registered copied text source {name} in workspace {workspace_id}")
    return src


@router.post("/email", response_model=Source)
def add_email_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    payload: EmailCreate = Body(...),
):
    """Add pasted email content as a source for the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    subject = payload.subject.strip()
    if not subject:
        subject = "Untitled Email"

    # Standardize name extension
    name = f"Email: {subject}"
    if not name.endswith(".eml"):
        name = f"{name}.eml"

    upload_dir = get_sources_upload_dir(workspace_id)
    upload_dir.mkdir(parents=True, exist_ok=True)

    source_id = str(uuid.uuid4())
    filename = f"{source_id}_email.eml"
    try:
        dest_path = safe_file_path(upload_dir, filename)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Save formatted email text to disk so the EmailProcessor can parse it just like a regular EML file
    email_content = f"From: {payload.sender}\nTo: {payload.recipient}\nSubject: {payload.subject}\n\n{payload.body}"
    try:
        with open(dest_path, "w", encoding="utf-8") as f:
            f.write(email_content)
    except Exception as e:
        logger.error(f"Failed to write email file {filename} to disk: {e}")
        raise HTTPException(status_code=500, detail="Failed to save email source")

    size_bytes = dest_path.stat().st_size

    current_sources = load_sources(workspace_id)
    src = Source(
        id=source_id,
        name=name,
        type="email",
        path=str(dest_path.relative_to(settings.storage_dir.parent)),
        url=None,
        added_at=datetime.now(timezone.utc),
        size_bytes=size_bytes,
        status="pending",
    )

    current_sources.append(src)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Registered email source {name} in workspace {workspace_id}")
    return src


@router.delete("/{source_id}")
def delete_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique workspace ID"
    ),
    source_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The unique source ID"
    ),
):
    """Delete a source from the workspace."""
    workspace_dir = get_workspace_dir(workspace_id)
    if not workspace_dir.exists():
        raise HTTPException(status_code=404, detail="Workspace not found")

    current_sources = load_sources(workspace_id)
    source_to_delete = None

    for src in current_sources:
        if src.id == source_id:
            source_to_delete = src
            break

    if not source_to_delete:
        raise HTTPException(status_code=404, detail="Source not found")

    # Delete file if it exists
    if source_to_delete.path:
        file_path = FilePath(source_to_delete.path)
        if file_path.exists():
            try:
                file_path.unlink()
            except Exception as e:
                logger.error(f"Failed to delete source file {file_path}: {e}")

    # Delete chunks from SQLite database
    from app.core.database import delete_source_chunks

    try:
        delete_source_chunks(workspace_id, source_id)
    except Exception as e:
        logger.error(f"Failed to delete SQLite chunks for source {source_id}: {e}")

    # Update list & save
    current_sources.remove(source_to_delete)
    save_sources(workspace_id, current_sources)
    update_workspace_sources_count(workspace_id, len(current_sources))

    logger.info(f"Deleted source {source_id} from workspace {workspace_id}")
    return {"status": "ok", "message": f"Source {source_id} deleted successfully"}


@router.get("/{source_id}/pages/{page_num}")
async def get_pdf_page_image(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    source_id: str = Path(..., pattern=r"^[0-9a-f-]{36}$", description="The source ID"),
    page_num: int = Path(..., gt=0, description="The page number to render (1-based)"),
):
    """
    Renders a specific page of a PDF source as a PNG image dynamically on-the-fly and streams it.
    """
    from fastapi.responses import StreamingResponse
    import io
    import fitz

    current_sources = load_sources(workspace_id)
    source = None
    for src in current_sources:
        if src.id == source_id:
            source = src
            break

    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    if source.type != "pdf":
        raise HTTPException(status_code=400, detail="Source is not a PDF file")

    pdf_path = settings.storage_dir.parent / source.path
    if not pdf_path.exists():
        raise HTTPException(
            status_code=404, detail="Original PDF file not found on disk"
        )

    try:
        doc = fitz.open(str(pdf_path))
        if page_num > len(doc):
            doc.close()
            raise HTTPException(
                status_code=400,
                detail=f"Page number {page_num} exceeds document length ({len(doc)})",
            )

        page = doc.load_page(page_num - 1)
        pix = page.get_pixmap(dpi=150)
        img_data = pix.tobytes("png")
        doc.close()

        return StreamingResponse(io.BytesIO(img_data), media_type="image/png")
    except Exception as e:
        logger.error(f"Error rendering PDF page {page_num} for source {source_id}: {e}")
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Failed to render page: {e}")


@router.get("/{source_id}/download")
def download_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    source_id: str = Path(..., pattern=r"^[0-9a-f-]{36}$", description="The source ID"),
):
    """
    Downloads or streams the original source file.
    """
    from fastapi.responses import FileResponse

    current_sources = load_sources(workspace_id)
    source = None
    for src in current_sources:
        if src.id == source_id:
            source = src
            break

    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    if not source.path:
        raise HTTPException(
            status_code=400, detail="Source does not have a local file path"
        )

    file_path = settings.storage_dir.parent / source.path
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found on disk")

    return FileResponse(file_path, filename=source.name)


@router.post("/{source_id}/retry")
def retry_source(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    source_id: str = Path(..., pattern=r"^[0-9a-f-]{36}$", description="The source ID"),
):
    """
    Resets a failed source's status to pending.
    """
    current_sources = load_sources(workspace_id)
    source = None
    for src in current_sources:
        if src.id == source_id:
            source = src
            break

    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    source.status = "pending"
    save_sources(workspace_id, current_sources)
    return {"status": "ok", "message": "Source status reset to pending"}


@router.get("/{source_id}/preview")
def get_source_preview(
    workspace_id: str = Path(..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"),
    source_id: str = Path(..., pattern=r"^[0-9a-f-]{36}$", description="The source ID"),
):
    """
    Returns preview metadata for a source (page count for PDFs, text content snippet, media details).
    """
    current_sources = load_sources(workspace_id)
    source = next((src for src in current_sources if src.id == source_id), None)
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")

    preview_data = {
        "id": source.id,
        "name": source.name,
        "type": source.type,
        "status": source.status,
        "size_bytes": source.size_bytes,
        "page_count": 0,
        "preview_text": None,
        "url": source.url,
        "download_url": f"/workspaces/{workspace_id}/sources/{source.id}/download",
    }

    if source.type == "pdf" and source.path:
        file_path = settings.storage_dir.parent / source.path
        if file_path.exists():
            try:
                import fitz
                doc = fitz.open(str(file_path))
                preview_data["page_count"] = len(doc)
                if len(doc) > 0:
                    preview_data["preview_text"] = doc[0].get_text("text")[:2000]
                doc.close()
            except Exception as e:
                logger.error(f"Error reading PDF preview for {source.id}: {e}")

    elif source.type in ["text", "code"] and source.path:
        file_path = settings.storage_dir.parent / source.path
        if file_path.exists():
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    preview_data["preview_text"] = f.read(5000)
            except Exception as e:
                logger.error(f"Error reading text file preview for {source.id}: {e}")

    return preview_data
