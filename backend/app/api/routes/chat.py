# app/api/routes/chat.py
# Purpose: APIRouter for workspace chat/query operations.
# Responsibilities: Exposes query endpoint to invoke RAG engine retrieve_and_generate.

from fastapi import APIRouter, HTTPException, Path
import logging

from app.core.config import settings
from app.core.retriever import retrieve_and_generate
from app.models.chat import ChatRequest, ChatResponse

logger = logging.getLogger("kivo.chat")
router = APIRouter()

@router.post("", response_model=ChatResponse)
async def query_workspace(
    workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The workspace ID"),
    payload: ChatRequest = None
):
    """
    Query the workspace RAG pipeline.
    Retrieves relevant parent chunks and generates a cited answer using Ollama.
    """
    logger.info(f"Received query for workspace {workspace_id}: '{payload.message}'")
    try:
        model_to_use = payload.model_name if payload.model_name else settings.ollama_default_model
        from app.core.ollama_manager import ensure_only_model
        await ensure_only_model(model_to_use, payload.ollama_url)
        res = await retrieve_and_generate(
            workspace_id=workspace_id,
            question=payload.message,
            model_name=model_to_use,
            is_strict=payload.is_strict,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url,
            history=payload.history
        )
        if res.get("routing_mode") == "ERROR" or res["answer"].startswith("Error"):
            # Check if it was a real connection error or missing index
            raise HTTPException(status_code=500, detail=res["answer"])
            
        return ChatResponse(
            answer=res["answer"],
            plain_answer=res["plain_answer"],
            citations=res["citations"],
            latency_ms=res["latency_ms"],
            recommended_questions=res.get("recommended_questions", [])
        )
    except Exception as e:
        logger.error(f"Error querying workspace {workspace_id}: {e}", exc_info=True)
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail="An internal error occurred while processing your query. Please try again.")

@router.post("/stream")
async def query_workspace_stream(
    workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The workspace ID"),
    payload: ChatRequest = None
):
    """
    Query the workspace RAG pipeline with streaming.
    Yields JSON Server-Sent Events (SSE) tokens and final citation metadata.
    """
    from fastapi.responses import StreamingResponse
    from app.core.retriever import retrieve_and_generate_stream

    if not payload or not payload.message:
        raise HTTPException(status_code=400, detail="Query message cannot be empty")
        
    logger.info(f"Received streaming query for workspace {workspace_id}: '{payload.message}', is_strict: {payload.is_strict}")
    
    model_to_use = payload.model_name if payload.model_name else settings.ollama_default_model
    from app.core.ollama_manager import ensure_only_model
    await ensure_only_model(model_to_use, payload.ollama_url)
    return StreamingResponse(
        retrieve_and_generate_stream(
            workspace_id=workspace_id,
            question=payload.message,
            model_name=model_to_use,
            is_strict=payload.is_strict,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url,
            history=payload.history
        ),
        media_type="text/event-stream"
    )

@router.post("/feedback")
def submit_query_feedback(
    workspace_id: str = Path(..., regex=r"^[0-9a-f-]{36}$", description="The workspace ID"),
    payload: dict = None
):
    """
    Saves user feedback (helpful/irrelevant) for a specific chunk or citation.
    """
    import json
    from datetime import datetime, timezone
    logger.info(f"Feedback received for workspace {workspace_id}: {payload}")
    feedback_file = settings.workspaces_dir / workspace_id / "feedback.json"
    
    try:
        feedback_data = []
        if feedback_file.exists():
            with open(feedback_file, "r") as f:
                feedback_data = json.load(f)
                
        if not payload:
            payload = {}
        payload["timestamp"] = datetime.now(timezone.utc).isoformat()
        feedback_data.append(payload)
        
        with open(feedback_file, "w") as f:
            json.dump(feedback_data, f, indent=2)
            
        return {"status": "success", "message": "Feedback recorded"}
    except Exception as e:
        logger.error(f"Failed to save feedback for workspace {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to save feedback")

