from fastapi import APIRouter, HTTPException
import logging

from app.core.config import settings
from app.core.retriever import retrieve_and_generate_universal
from app.models.chat import UniversalChatRequest, ChatResponse

logger = logging.getLogger("kivo.universal_chat")
router = APIRouter()

@router.post("", response_model=ChatResponse)
async def query_universal(payload: UniversalChatRequest):
    """
    Query the universal RAG pipeline across multiple workspaces.
    Retrieves relevant parent chunks, ranks/merges, and generates a cited answer using Ollama.
    """
    logger.info(f"Received universal query across workspaces {payload.workspace_ids}: '{payload.message}'")
    if not payload.workspace_ids:
        raise HTTPException(status_code=400, detail="At least one workspace ID must be provided in the search scope.")
    try:
        model_to_use = payload.model_name if payload.model_name else settings.ollama_default_model
        res = await retrieve_and_generate_universal(
            workspace_ids=payload.workspace_ids,
            question=payload.message,
            model_name=model_to_use,
            is_strict=payload.is_strict,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url
        )
        if res.get("routing_mode") == "ERROR" or res["answer"].startswith("Error"):
            raise HTTPException(status_code=500, detail=res["answer"])
            
        return ChatResponse(
            answer=res["answer"],
            plain_answer=res["plain_answer"],
            citations=res["citations"],
            latency_ms=res["latency_ms"],
            recommended_questions=res.get("recommended_questions", [])
        )
    except Exception as e:
        logger.error(f"Error in universal query: {e}", exc_info=True)
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail="An internal error occurred while processing your query. Please try again.")

@router.post("/stream")
async def query_universal_stream(payload: UniversalChatRequest):
    """
    Query the universal RAG pipeline across multiple workspaces with streaming.
    Yields JSON Server-Sent Events (SSE) tokens and final citation metadata.
    """
    from fastapi.responses import StreamingResponse
    from app.core.retriever import retrieve_and_generate_universal_stream

    if not payload or not payload.message:
        raise HTTPException(status_code=400, detail="Query message cannot be empty")
    if not payload.workspace_ids:
        raise HTTPException(status_code=400, detail="At least one workspace ID must be provided in the search scope.")
        
    logger.info(f"Received universal streaming query across workspaces {payload.workspace_ids}: '{payload.message}', is_strict: {payload.is_strict}")
    
    model_to_use = payload.model_name if payload.model_name else settings.ollama_default_model
    return StreamingResponse(
        retrieve_and_generate_universal_stream(
            workspace_ids=payload.workspace_ids,
            question=payload.message,
            model_name=model_to_use,
            is_strict=payload.is_strict,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url
        ),
        media_type="text/event-stream"
    )
