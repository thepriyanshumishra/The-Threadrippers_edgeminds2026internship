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
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    payload: ChatRequest = None,
):
    """
    Query the workspace RAG pipeline.
    Retrieves relevant parent chunks and generates a cited answer using Ollama.
    """
    if not payload or not payload.message or len(payload.message.strip()) == 0:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    if len(payload.message) > 8000:
        raise HTTPException(
            status_code=400, detail="Message too long (max 8000 characters)"
        )

    logger.info(f"Received query for workspace {workspace_id}: '{payload.message}'")
    try:
        model_to_use = (
            payload.model_name if payload.model_name else settings.ollama_default_model
        )
        from app.core.ollama_manager import ensure_only_model

        await ensure_only_model(model_to_use, payload.ollama_url)
        res = await retrieve_and_generate(
            workspace_id=workspace_id,
            question=payload.message,
            model_name=model_to_use,
            mode=payload.mode,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url,
            history=payload.history,
        )
        if res.get("routing_mode") == "ERROR" or res["answer"].startswith("Error"):
            # Check if it was a real connection error or missing index
            raise HTTPException(status_code=500, detail=res["answer"])

        from app.core.database import save_chat_message
        import uuid

        user_msg_id = str(uuid.uuid4())
        assistant_msg_id = str(uuid.uuid4())

        save_chat_message(
            workspace_id, user_msg_id, "user", payload.message, payload.mode, []
        )
        save_chat_message(
            workspace_id,
            assistant_msg_id,
            "assistant",
            res["answer"],
            payload.mode,
            res.get("citations", []),
        )

        return ChatResponse(
            answer=res["answer"],
            plain_answer=res["plain_answer"],
            citations=res["citations"],
            latency_ms=res["latency_ms"],
            recommended_questions=res.get("recommended_questions", []),
        )
    except Exception as e:
        logger.error(f"Error querying workspace {workspace_id}: {e}", exc_info=True)
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=500,
            detail="An internal error occurred while processing your query. Please try again.",
        )


@router.get("/history")
def get_workspace_chat_history(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    )
):
    """Retrieves all chat messages for a workspace in chronological order."""
    from app.core.database import get_chat_history

    try:
        return get_chat_history(workspace_id)
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to fetch chat history for {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch chat history")


@router.delete("/history")
def clear_workspace_chat_history(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    )
):
    """Clears all chat history for a workspace."""
    from app.core.database import clear_chat_history

    try:
        clear_chat_history(workspace_id)
        return {"status": "success", "message": "Chat history cleared"}
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        logger.error(f"Failed to clear chat history for {workspace_id}: {e}")
        raise HTTPException(status_code=500, detail="Failed to clear chat history")


@router.post("/stream")
async def query_workspace_stream(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    payload: ChatRequest = None,
):
    """
    Query the workspace RAG pipeline with streaming.
    Yields JSON Server-Sent Events (SSE) tokens and final citation metadata.
    """
    from fastapi.responses import StreamingResponse
    from app.core.retriever import retrieve_and_generate_stream
    from app.core.database import save_chat_message
    import uuid

    if not payload or not payload.message or len(payload.message.strip()) == 0:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    if len(payload.message) > 8000:
        raise HTTPException(
            status_code=400, detail="Message too long (max 8000 characters)"
        )

    user_msg_id = str(uuid.uuid4())
    save_chat_message(
        workspace_id, user_msg_id, "user", payload.message, payload.mode, []
    )

    logger.info(
        f"Received streaming query for workspace {workspace_id}: '{payload.message}', mode: {payload.mode}"
    )

    model_to_use = (
        payload.model_name if payload.model_name else settings.ollama_default_model
    )
    from app.core.ollama_manager import ensure_only_model

    await ensure_only_model(model_to_use, payload.ollama_url)

    async def wrapped_stream():
        full_text_parts = []
        final_citations = []

        async for chunk in retrieve_and_generate_stream(
            workspace_id=workspace_id,
            question=payload.message,
            model_name=model_to_use,
            mode=payload.mode,
            temperature=payload.temperature,
            similarity_threshold=payload.similarity_threshold,
            ollama_url=payload.ollama_url,
            history=payload.history,
        ):
            yield chunk
            if chunk.startswith("data: "):
                data_str = chunk[6:].strip()
                if data_str != "[DONE]":
                    try:
                        parsed = json.loads(data_str)
                        if "token" in parsed:
                            full_text_parts.append(parsed["token"])
                        if "citations" in parsed:
                            final_citations = parsed["citations"]
                    except Exception:
                        pass

        # Save assistant message once stream completes
        full_answer = "".join(full_text_parts).strip()
        if full_answer:
            assistant_msg_id = str(uuid.uuid4())
            save_chat_message(
                workspace_id,
                assistant_msg_id,
                "assistant",
                full_answer,
                payload.mode,
                final_citations,
            )

    return StreamingResponse(
        wrapped_stream(),
        media_type="text/event-stream",
        headers={"X-Accel-Buffering": "no"},
    )


@router.post("/feedback")
def submit_query_feedback(
    workspace_id: str = Path(
        ..., pattern=r"^[0-9a-f-]{36}$", description="The workspace ID"
    ),
    payload: dict = None,
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
