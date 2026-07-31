# app/core/retriever.py
try:
    import torch  # Prevent OpenMP/MKL conflict with faiss on macOS
except ImportError:
    pass
import re
import json
import time
import logging
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional
import numpy as np
from usearch.index import Index
import httpx
from collections import OrderedDict

# Max 5 workspaces in memory
MAX_CACHE_SIZE = 5
_workspace_index_cache = OrderedDict()


def _get_or_build_usearch_index(workspace_id: str, workspace_dir: Path) -> Index:
    usearch_file = workspace_dir / "index.usearch"
    faiss_file = workspace_dir / "index.faiss"

    if not usearch_file.exists():
        sources_file = workspace_dir / "sources.json"
        if faiss_file.exists() or sources_file.exists():
            logger.info(
                f"index.usearch not found for workspace {workspace_id}, but legacy/source files exist. Recompiling usearch index..."
            )
            from app.core.processors.vector_db import VectorDBProcessor

            try:
                processor = VectorDBProcessor()
                processor.process(workspace_id)
            except Exception as e:
                logger.error(
                    f"Failed to auto-recompile usearch index for workspace {workspace_id}: {e}"
                )

    if not usearch_file.exists():
        raise FileNotFoundError(
            f"Knowledge base index is not compiled for workspace {workspace_id}. Please process your sources first."
        )

    index = Index(ndim=768, metric="cos")
    index.load(str(usearch_file))
    return index


def get_cached_usearch_index(workspace_id: str, workspace_dir: Path) -> Index:
    if workspace_id in _workspace_index_cache:
        _workspace_index_cache.move_to_end(workspace_id)
        # Check file modified time in case it was updated
        cache_entry = _workspace_index_cache[workspace_id]
        usearch_file = workspace_dir / "index.usearch"
        if usearch_file.exists():
            mtime = usearch_file.stat().st_mtime
            if mtime == cache_entry["mtime"]:
                return cache_entry["index"]
            
    # Build or load
    index = _get_or_build_usearch_index(workspace_id, workspace_dir)
    usearch_file = workspace_dir / "index.usearch"
    mtime = usearch_file.stat().st_mtime if usearch_file.exists() else time.time()
    
    _workspace_index_cache[workspace_id] = {"index": index, "mtime": mtime}
    if len(_workspace_index_cache) > MAX_CACHE_SIZE:
        _workspace_index_cache.popitem(last=False)
        
    return index


import asyncio
import multiprocessing

MAX_RETRIES = 3
RETRY_DELAY = 1.5  # seconds


async def _call_ollama_with_retry(client, method, url, **kwargs):
    """Call Ollama with exponential backoff retry on connection errors."""
    for attempt in range(MAX_RETRIES):
        try:
            return await client.request(method, url, **kwargs)
        except httpx.ConnectError:
            if attempt < MAX_RETRIES - 1:
                await asyncio.sleep(RETRY_DELAY * (attempt + 1))
                continue
            raise httpx.ConnectError(
                f"Ollama is not running after {MAX_RETRIES} attempts. Please start Ollama."
            )
        except httpx.TimeoutException:
            raise httpx.TimeoutException(
                f"Ollama took too long to respond (timeout after {MAX_RETRIES} retries)."
            )


from app.core.config import settings
from app.core.processors.embeddings import get_embedding_model

logger = logging.getLogger("kivo.core.retriever")


def _load_source_maps(workspace_id: str) -> tuple[dict, dict]:
    """Load source metadata maps for citation resolution.
    Returns (source_id_to_name, source_id_to_url). On failure returns empty dicts."""
    from app.api.routes.sources import load_sources

    try:
        sources = load_sources(workspace_id)
        name_map = {s.id: s.name for s in sources}
        url_map = {s.id: s.url for s in sources if s.url}
        return name_map, url_map
    except Exception:
        return {}, {}


# Broad retrieval keywords regex
INTENT_REGEX = re.compile(
    r"\b(list\s+every|find\s+all|retrieve\s+all|timeline\s+of|summarize\s+references\s+to|discuss\s+all|retrieve\s+every|find\s+content\s+connected\s+to|find\s+every|retrieve\s+information|retrieve\s+content|list\s+all|show\s+all|what\s+are\s+all\s+the|enumerate|give\s+me\s+all|catalog)\b",
    re.IGNORECASE,
)

GLOBAL_SUMMARY_REGEX = re.compile(
    r"\b(what\s+is\s+(?:this\s+|the\s+)?workspace\s+about|what\s+does\s+this\s+workspace\s+contain|tell\s+me\s+about\s+this\s+workspace|what\s+is\s+(?:this\s+|the\s+)?video\s+about|what\s+is\s+(?:this\s+|the\s+)?document\s+about|what\s+is\s+(?:this\s+|the\s+)?file\s+about|what\s+are\s+(?:these\s+|the\s+)?sources\s+about|what\s+is\s+this\s+all\s+about|what\s+is\s+this\s+about|summarize|summary|overview|what\s+are\s+these\s+documents\s+about|what\s+does\s+this\s+talk\s+about|what\s+is\s+the\s+content\s+of|give\s+me\s+a\s+summary|explain\s+the\s+entire|main\s+idea|main\s+theme|what\s+are\s+the\s+key\s+takeaways|what\s+are\s+the\s+main\s+topics|what's\s+in\s+my\s+documents|overview\s+of|brief\s+me\s+on|tldr|tl;dr|key\s+points|main\s+ideas)\b",
    re.IGNORECASE,
)


# Token estimation helper
def estimate_tokens(text: str) -> int:
    return int(len(text.split()) * 1.3)


STRICT_QA_PROMPT = """You are an articulate, professional AI research assistant. Answer the user's question using the provided context chunks as your primary source of facts.

FORMATTING & RESPONSE GUIDELINES:
- **Structure**: Organize your response logically. Use clear section headers (`### Section Title`) for multi-part answers.
- **Readability**: Write in concise, easy-to-understand language. Use short paragraphs (2-3 sentences max).
- **Highlights**: Use **bold text** to highlight key terms, commands, or critical actions.
- **Lists**: Use clean bulleted lists (`- **Concept**: Details...`) for steps, features, or components.
- **Code & Data**: Use code blocks with appropriate language tags for code/commands. Use markdown tables for structured comparisons.
- **Grounding**: Synthesize information directly from the provided context. Do NOT invent facts not present in the context.
- **Language**: Respond in the same language as the user's question.

Context:
{context}

Question:
{question}

Answer:"""

DEFAULT_QA_PROMPT = """You are a helpful, knowledgeable AI assistant. Use the provided context chunks as your PRIMARY source of facts.

FORMATTING & RESPONSE GUIDELINES:
- **Structure**: Present your answer with clean Markdown styling. Use section headers (`### Title`) where helpful.
- **Readability**: Keep explanations simple, clear, and direct. Break long explanations into short paragraphs.
- **Highlights**: Use **bold text** for key terms, concepts, or important takeaways.
- **Lists**: Use bullet points (`- **Key Point**: explanation`) for easy scanning.
- **General Knowledge**: If parts of the question are not covered in the context, you may supplement with general knowledge — prefix those supplemental sections with `> **Note**: Based on general knowledge — `.
- **Language**: Respond in the same language as the user's question.

Context:
{context}

Question:
{question}

Answer:"""

CREATIVE_QA_PROMPT = """You are a brilliant general-purpose AI assistant. Answer the user's question using your pre-trained general knowledge. Give thorough, structured answers using markdown.
For factual claims, indicate if uncertain: add *(unverified)* qualifier.
Respond in the same language as the user's question.
Format answers with headers, bullets, and code blocks where appropriate.
Do not mention or cite any document chunks or source files.

Question:
{question}

Answer:"""

META_RETRIEVAL_PROMPT = """You are a synthesis and retrieval assistant. Summarize and aggregate information across the provided context chunks to give a comprehensive, beautifully structured overview.

FORMATTING & RESPONSE GUIDELINES:
- **Structure**: Use clear Markdown headers (`### Title`), bullet lists with **bold titles**, and comparison tables where appropriate.
- **Readability**: Ensure explanations are clear, concise, and easy to read.
- **Language**: Respond in the same language as the user's question.

Context:
{context}

Question:
{question}

Answer:"""


def get_adaptive_system_prompts(
    model_name: str, mode: str, is_meta_retrieval: bool = False
) -> str:
    """
    Returns an optimized system prompt depending on the model's capabilities and size.
    Prevents smaller or reasoning models from getting stuck or failing to format.
    """
    model_name_lower = model_name.lower()

    # 1. Identify model category
    is_reasoning_model = (
        "r1" in model_name_lower
        or "reasoning" in model_name_lower
        or "o1" in model_name_lower
    )
    is_small_model = any(
        kw in model_name_lower for kw in ["1.5b", "1b", "2b", "3b", "smollm", "tiny"]
    )
    is_default_qwen = (
        "qwen2.5:1.5b" in model_name_lower or "qwen2.5" in model_name_lower
    )

    if is_reasoning_model:
        # Reasoning models output <think>...</think>. Keep prompt simple and direct.
        # Too many constraints cause reasoning models to loop or fail reasoning.
        if mode in ["strict", "default"]:
            if is_meta_retrieval:
                return """You are a grounded meta-retrieval assistant.
Answer the user's question by aggregating references from the provided context chunks.
Keep your answer factual and direct. You must cite the chunk ID of the context for every claim you make using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. [doc1_p4]). Never write placeholder IDs.
Do not invent facts. If the context does not contain the answer, politely refuse.

Context:
{context}

Question:
{question}

Answer:"""
            else:
                return """You are a grounded QA assistant.
Answer the user's question using the provided context chunks.
Keep your explanation factual, clear, and direct. You must cite the chunk ID of the context for every claim you make using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. [doc1_p4]) at the end of the sentence or statement. Never write placeholder IDs.
If the context does not cover the topic, state that clearly.

Context:
{context}

Question:
{question}

Answer:"""
        else:
            return """You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge.
Do not mention or cite any document chunks or source files.
Write your response in clean Markdown.

Question:
{question}

Answer:"""

    elif is_small_model and not is_default_qwen:
        # Small non-Qwen models (e.g. Gemma 2B, Llama 3.2 3B, SmolLM2 1.7B)
        # Avoid demanding tables, complex nesting, bolding, etc. to prevent overloading/stuck states.
        if mode in ["strict", "default"]:
            if is_meta_retrieval:
                return """You are a grounded meta-retrieval assistant.
Answer the user's question using the provided context chunks.
Summarize the key information clearly. Cite the chunk ID of the context using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. [doc1_p4]) at the end of statements. Never write placeholder IDs.
If the context is empty, state that the topic is not covered.

Context:
{context}

Question:
{question}

Answer:"""
            else:
                return """You are a grounded QA assistant.
Answer the user's question using the provided context chunks as your source of facts.
Explain the answer simply and directly. Do not make up facts.
Cite the chunk ID using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. [doc1_p4]) for every factual claim. Never write placeholder IDs.
If the context does not contain the answer, state that the topic is not covered.

Context:
{context}

Question:
{question}

Answer:"""
        else:
            return """You are a helpful AI assistant. Answer the user's question using your pre-trained knowledge.
Keep your answer clear and concise. Do not cite document chunks.

Question:
{question}

Answer:"""

    else:
        # Highly capable models (e.g. Qwen 2.5 1.5B/7B, Llama 3.1 8B, DeepSeek R1 8B/14B)
        # We can use the full rich system prompts.
        if mode in ["strict", "default"]:
            if is_meta_retrieval:
                return """You are a grounded meta-retrieval assistant. The user is asking for a comprehensive list or summary of references across the entire knowledge base.
Analyze the provided context chunks, aggregate all relevant instances, and synthesize them.

If the workspace system instructions specify a custom language (e.g. Hindi, French, Spanish, German, etc.) or formatting constraint, you MUST translate the facts from the context and write your entire response (including explanations and sentences) strictly in that requested language/format.

Format your response using professional Markdown:
1. Use bold text to highlight key concepts, terms, or actions.
2. Use bulleted lists for unordered points, and numbered lists for sequences or steps. Use lettered sub-bullets (a, b, c) if nesting is required.
3. Use tables when presenting comparative data, key-value pairs, or structured details.
4. Use code blocks with the appropriate language tag (e.g. ```bash, ```python, etc.) for commands, code snippets, or configuration.
5. Use italics for emphasis, definitions, or quotes.

For every factual claim you make, you MUST cite the chunk ID of the context where the information was found using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. [doc123_p4]). Never write placeholder IDs.

Context:
{context}

Question:
{question}

Answer:"""
            else:
                return STRICT_QA_PROMPT if mode == "strict" else DEFAULT_QA_PROMPT
        else:
            return CREATIVE_QA_PROMPT
def _calculate_overlap_score(text_a: str, text_b: str) -> float:
    """Calculate token overlap (Jaccard similarity) between generated answer and context chunk."""
    if not text_a or not text_b:
        return 0.0
    words_a = set(re.findall(r"\w{3,}", text_a.lower()))
    words_b = set(re.findall(r"\w{3,}", text_b.lower()))
    if not words_a or not words_b:
        return 0.0
    stop_words = {
        "the", "and", "for", "that", "this", "with", "from", "your", "have",
        "are", "was", "were", "been", "will", "would", "could", "should", "what",
        "where", "when", "which", "who", "how", "all", "any", "both", "each"
    }
    words_a -= stop_words
    words_b -= stop_words
    if not words_a or not words_b:
        return 0.0
    intersection = words_a.intersection(words_b)
    union = words_a.union(words_b)
    return len(intersection) / len(union) if union else 0.0


def sanitize_response(
    answer: str,
    parent_chunks: List[Dict[str, Any]] = None,
    source_id_to_name: Dict[str, str] = None,
    source_id_to_url: Dict[str, str] = None,
) -> Tuple[str, List[Dict[str, Any]], str]:
    """
    Removes XML tags, cleans up response text, performs post-hoc grounding citation matching,
    and falls back to retrieved candidates if no inline tags exist.
    """
    if not answer or not isinstance(answer, str):
        return "", [], ""

    # 1. Remove XML tags like <chunk ...> and </chunk>
    answer_clean = re.sub(r"</?chunk[^>]*>", "", answer)

    # Strip any stray hallucinated tags like [chunk_1], [Source 1], [doc1_p2], etc.
    pattern = re.compile(r"\[[^\]]*?([a-zA-Z0-9_-]+_[pc]\d+)[^\]]*?\]")
    matches = list(pattern.finditer(answer_clean))

    unique_citations = []
    full_to_clean = {}
    for match in matches:
        full_tag = match.group(0)
        clean_id = match.group(1)
        full_to_clean[full_tag] = clean_id
        if clean_id not in unique_citations:
            unique_citations.append(clean_id)

    # 2. Post-Hoc Grounding Pass: match parent chunks by token overlap or high vector relevance score
    if not unique_citations and parent_chunks:
        scored_parents = []
        for p in parent_chunks:
            overlap = _calculate_overlap_score(answer_clean, p.get("text", ""))
            vec_score = p.get("score", 0.0)
            combined_relevance = max(overlap, vec_score if vec_score >= 0.65 else 0.0)
            scored_parents.append((overlap, combined_relevance, p))

        # Sort by combined relevance descending
        scored_parents.sort(key=lambda x: x[1], reverse=True)

        # Only include parent chunks that either have text token overlap (>= 0.08) OR high vector relevance (>= 0.65)
        matched_parents = [
            p for overlap, comb, p in scored_parents
            if (overlap >= 0.08 or p.get("score", 0.0) >= 0.65)
        ]

        for p in matched_parents:
            p_id = p.get("id")
            if p_id and p_id not in unique_citations:
                unique_citations.append(p_id)

    citations_meta = []
    answer_footnoted = answer_clean
    answer_plain = answer_clean

    # Strip out any remaining inline [chunk_x] or [Source N] tags from the visible answer text
    answer_footnoted = re.sub(r"\[(?:chunk_|Source\s*|doc_?)\w+\]", "", answer_footnoted, flags=re.IGNORECASE)
    answer_plain = re.sub(r"\[(?:chunk_|Source\s*|doc_?)\w+\]", "", answer_plain, flags=re.IGNORECASE)
    for full_tag in full_to_clean.keys():
        answer_footnoted = answer_footnoted.replace(full_tag, "")
        answer_plain = answer_plain.replace(full_tag, "")

    for i, clean_id in enumerate(unique_citations, 1):
        source_id = None
        if "_p" in clean_id:
            source_id = clean_id.split("_p")[0]
        elif "_c" in clean_id:
            source_id = clean_id.split("_c")[0]

        source_name = "Source Document"
        if source_id and source_id_to_name and source_id in source_id_to_name:
            source_name = source_id_to_name[source_id]

        snippet = ""
        pages = []
        start_times = []
        score = 0.0
        if parent_chunks:
            for p in parent_chunks:
                if p.get("id") == clean_id:
                    snippet = p.get("text", "")
                    pages = p.get("pages", [])
                    start_times = p.get("start_times", [])
                    overlap = _calculate_overlap_score(answer_clean, snippet)
                    vec_score = p.get("score", 0.0)
                    # Dynamic relevance score: blend of text overlap and vector score (0-100%)
                    raw_score = max(overlap * 100, vec_score * 100)
                    score = min(100.0, max(15.0, raw_score)) / 100.0
                    break

        timestamp_url = None
        if start_times and source_id and source_id_to_url:
            url = source_id_to_url.get(source_id)
            if url and ("youtube.com" in url or "youtu.be" in url):
                sec = int(start_times[0])
                timestamp_url = f"{url}&t={sec}s" if "?" in url else f"{url}?t={sec}s"

        citations_meta.append(
            {
                "index": i,
                "raw_id": clean_id,
                "source_id": source_id,
                "source_name": source_name,
                "snippet": snippet,
                "pages": pages,
                "start_times": start_times,
                "timestamp_url": timestamp_url,
                "score": score,
            }
        )

        # Replace all instances of the full tag with the footnote or empty string
        for full_tag, cid in full_to_clean.items():
            if cid == clean_id:
                answer_footnoted = answer_footnoted.replace(full_tag, f"[{i}]")

    # Clean up excessive spacing and pre-punctuation spaces
    answer_footnoted = re.sub(r" +", " ", answer_footnoted).strip()
    answer_plain = re.sub(r" +", " ", answer_plain).strip()
    for char in [".", ",", ";", "?", "!"]:
        answer_footnoted = answer_footnoted.replace(f" {char}", char)
        answer_plain = answer_plain.replace(f" {char}", char)

    return answer_footnoted, citations_meta, answer_plain


async def _rewrite_query_if_needed(
    question: str,
    history: Optional[List[Dict[str, str]]],
    ollama_url: Optional[str],
    model_name: str,
) -> str:
    # If no history, or no pronouns found in the question, return the original question
    if not history or not PRONOUN_PATTERN.search(question):
        return question

    # Construct history string
    history_str = ""
    for turn in history[-3:]:  # only last 3 turns to keep it super lightweight
        role = "User" if turn.get("role") == "user" else "Assistant"
        content = turn.get("content", "").strip()
        history_str += f"{role}: {content}\n"

    prompt = (
        "Instructions: Resolve any pronouns (like he, she, it, this, that) in the user's latest question "
        "using the conversation history to make it a self-contained search query.\n"
        "Return ONLY the rewritten search query. Do not add any introduction, explanations, or quotes.\n\n"
        f"Conversation:\n{history_str}"
        f"User's latest question: {question}\n"
        "Rewritten search query:"
    )

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.0,
            "num_predict": 30,  # limit response length to avoid runaway generation
            "num_ctx": 1024,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=5.0)) as client:
            response = await _call_ollama_with_retry(client, "POST", url, json=payload)
            if response.status_code == 200:
                rewritten = response.json().get("response", "").strip()
                # Clean up any quotes
                rewritten = rewritten.strip("\"'")
                if rewritten:
                    logger.info(f"Rewrote query: '{question}' -> '{rewritten}'")
                    return rewritten
    except Exception as e:
        logger.error(f"Failed to rewrite query: {e}")

    return question


import sqlite3
import hashlib


def get_cache_db_path(workspace_id: str) -> Path:
    return settings.workspaces_dir / workspace_id / "rag_cache.db"


def init_cache_db(workspace_id: str):
    db_path = get_cache_db_path(workspace_id)
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS rag_cache (
            query_hash TEXT PRIMARY KEY,
            prompt TEXT,
            routing_mode TEXT,
            retrieved_child_chunks TEXT,
            retrieved_parent_chunks TEXT,
            parent_ids_used TEXT,
            refusal_msg TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    conn.close()


def clear_rag_cache(workspace_id: str):
    db_path = get_cache_db_path(workspace_id)
    if db_path.exists():
        try:
            db_path.unlink()
            logger.info(f"Cleared RAG cache for workspace {workspace_id}")
        except Exception as e:
            logger.error(f"Failed to clear RAG cache for {workspace_id}: {e}")


def invalidate_workspace_cache(workspace_id: str):
    """Alias for clear_rag_cache as requested."""
    clear_rag_cache(workspace_id)


def get_cached_rag_prompt(
    workspace_id: str,
    question: str,
    model_name: str,
    mode: str,
    similarity_threshold: Optional[float],
    history: Optional[List[Dict[str, str]]],
) -> Optional[
    Tuple[
        str, str, List[Dict[str, Any]], List[Dict[str, Any]], List[str], Optional[str]
    ]
]:
    db_path = get_cache_db_path(workspace_id)
    if not db_path.exists():
        return None
    try:
        key_str = f"{question}||{model_name}||{mode}||{similarity_threshold}||{json.dumps(history)}"
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()

        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        cursor = conn.cursor()
        cursor.execute(
            "SELECT prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg FROM rag_cache WHERE query_hash = ?",
            (key_hash,),
        )
        row = cursor.fetchone()
        conn.close()

        if row:
            (
                prompt,
                routing_mode,
                child_chunks_json,
                parent_chunks_json,
                parent_ids_json,
                refusal_msg,
            ) = row
            child_chunks = json.loads(child_chunks_json)
            parent_chunks = json.loads(parent_chunks_json)
            parent_ids = json.loads(parent_ids_json)
            logger.info(f"RAG Cache Hit for query: '{question}'")
            return (
                prompt,
                routing_mode,
                child_chunks,
                parent_chunks,
                parent_ids,
                refusal_msg,
            )
    except Exception as e:
        logger.error(f"Error reading RAG cache for workspace {workspace_id}: {e}")
    return None


def set_cached_rag_prompt(
    workspace_id: str,
    question: str,
    model_name: str,
    mode: str,
    similarity_threshold: Optional[float],
    history: Optional[List[Dict[str, str]]],
    prompt: str,
    routing_mode: str,
    child_chunks: List[Dict[str, Any]],
    parent_chunks: List[Dict[str, Any]],
    parent_ids: List[str],
    refusal_msg: Optional[str],
):
    try:
        init_cache_db(workspace_id)
        db_path = get_cache_db_path(workspace_id)

        key_str = f"{question}||{model_name}||{mode}||{similarity_threshold}||{json.dumps(history)}"
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()

        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT OR REPLACE INTO rag_cache 
            (query_hash, prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg) 
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                key_hash,
                prompt,
                routing_mode,
                json.dumps(child_chunks),
                json.dumps(parent_chunks),
                json.dumps(parent_ids),
                refusal_msg,
            ),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Error writing RAG cache for workspace {workspace_id}: {e}")


def _prepare_rag_prompt(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    similarity_threshold: Optional[float] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Tuple[
    str, str, List[Dict[str, Any]], List[Dict[str, Any]], List[str], Optional[str]
]:
    cached = get_cached_rag_prompt(
        workspace_id, question, model_name, mode, similarity_threshold, history
    )
    if cached is not None:
        return cached

    refusal_msg = None
    workspace_dir = settings.workspaces_dir / workspace_id
    usearch_file = workspace_dir / "index.usearch"
    faiss_file = workspace_dir / "index.faiss"

    if not usearch_file.exists() and not faiss_file.exists():
        raise FileNotFoundError(
            "Knowledge base index is not compiled. Please process your sources first."
        )

    # 1. Intent Routing
    is_global_summary = bool(GLOBAL_SUMMARY_REGEX.search(question))
    routing_mode = "GLOBAL_SUMMARY" if is_global_summary else "STANDARD_QA"
    k = 3  # Optimized Top-K

    is_meta_retrieval = False
    if not is_global_summary and INTENT_REGEX.search(question):
        routing_mode = "META_RETRIEVAL"
        k = 6
        is_meta_retrieval = True

    system_prompt = get_adaptive_system_prompts(
        model_name, mode, is_meta_retrieval=is_meta_retrieval
    )

    logger.info(f"Question routed to {routing_mode} (Top-K={k}), mode={mode}")

    retrieved_child_chunks = []
    retrieved_parent_chunks = []
    parent_ids_used = []
    context_parts = []

    if is_global_summary:
        # Load sequential parent chunks from SQLite instead of doing similarity search
        from app.core.database import get_all_parent_chunks_ordered

        try:
            db_parents = get_all_parent_chunks_ordered(workspace_id)
        except FileNotFoundError:
            raise FileNotFoundError("Workspace has been deleted.")
        except Exception as e:
            logger.error(f"Error loading sequential parent chunks: {e}")
            db_parents = []

        current_tokens = 0
        for p in db_parents:
            p_text = p["text"]
            p_tokens = estimate_tokens(p_text)
            if current_tokens + p_tokens > max_parent_tokens:
                logger.info(
                    f"Parent chunk {p['id']} excluded. Adding it would exceed budget ({current_tokens + p_tokens} > {max_parent_tokens})."
                )
                continue
            current_tokens += p_tokens
            context_parts.append(f'<chunk id="{p["id"]}">\n{p_text}\n</chunk>')
            parent_ids_used.append(p["id"])
            retrieved_parent_chunks.append(
                {"id": p["id"], "text": p_text, "score": 1.0}
            )
    else:
        # Load or compile usearch index
        index = get_cached_usearch_index(workspace_id, workspace_dir)

        # 2. Vector Search (Child Chunks)
        model = get_embedding_model()
        query_emb = model.encode([question], normalize_embeddings=True)[0]
        query_contiguous = query_emb.copy().astype(np.float32)

        results = index.search(query_contiguous, k)
        scores = [[1.0 - d for d in results.distances]]
        indices = [results.keys]

        # Mode-specific similarity threshold check for GTE embeddings (768-dim)
        top_score = scores[0][0] if (len(scores) > 0 and len(scores[0]) > 0) else 0.0
        strict_threshold = 0.68
        default_threshold = 0.65

        if mode == "strict":
            if top_score < strict_threshold:
                refusal_msg = "I couldn't find information about this in your documents. In Strict mode, answers are strictly limited to your uploaded sources. Try rephrasing your question or switch to Default mode."
                return "", routing_mode, [], [], [], refusal_msg
        elif mode == "default":
            if top_score < default_threshold:
                logger.info(f"Top chunk similarity ({top_score:.3f}) below default threshold ({default_threshold}) — answering using general AI knowledge.")
                # Do not load irrelevant chunks into context for default mode when query is out-of-domain
                scores = [[]]
                indices = [[]]

        valid_indices = [int(idx) for idx in indices[0] if idx >= 0]

        # Load matching child chunks from SQLite
        from app.core.database import (
            get_child_chunks_by_global_indices,
            get_parent_chunks_by_ids,
        )

        db_chunks = get_child_chunks_by_global_indices(workspace_id, valid_indices)
        chunks_by_global_idx = {c["global_vector_index"]: c for c in db_chunks}

        # Collect unique parent chunks sorted by similarity
        parent_keys_seen = set()
        parent_records = []  # List of {"score": float, "parent_id": str}

        for rank, (score, chunk_idx) in enumerate(zip(scores[0], indices[0]), 1):
            chunk_idx_int = int(chunk_idx)
            if chunk_idx_int in chunks_by_global_idx:
                c_chunk = chunks_by_global_idx[chunk_idx_int]
                parent_id = c_chunk["parent_id"]

                c_record = {
                    "rank": rank,
                    "score": float(score),
                    "id": c_chunk["id"],
                    "text": c_chunk["text"],
                    "parent_id": parent_id,
                    "metadata": c_chunk.get("metadata", {}),
                }
                retrieved_child_chunks.append(c_record)

                if parent_id is not None:
                    if parent_id not in parent_keys_seen:
                        parent_keys_seen.add(parent_id)
                        parent_records.append(
                            {"score": float(score), "parent_id": parent_id}
                        )

        # Sort parent records in descending order of child chunk similarity score
        parent_records.sort(key=lambda x: x["score"], reverse=True)

        # 3. Load Parents and enforce budget (max 2000 tokens for context budgeting)
        parent_ids = [
            r["parent_id"] for r in parent_records if r["parent_id"] is not None
        ]
        db_parents = get_parent_chunks_by_ids(workspace_id, parent_ids)
        parents_by_id = {p["id"]: p["text"] for p in db_parents}

        current_tokens = 0
        for p_rec in parent_records:
            p_id = p_rec["parent_id"]
            if p_id in parents_by_id:
                p_text = parents_by_id[p_id]
                p_tokens = estimate_tokens(p_text)

                # Check context budget
                if current_tokens + p_tokens > max_parent_tokens:
                    logger.info(
                        f"Parent chunk {p_id} ({p_tokens} tokens) excluded. Adding it would exceed budget ({current_tokens + p_tokens} > {max_parent_tokens})."
                    )
                    continue

                current_tokens += p_tokens
                context_parts.append(f'<chunk id="{p_id}">\n{p_text}\n</chunk>')
                parent_ids_used.append(p_id)
                pages = []
                start_times = []
                for c in retrieved_child_chunks:
                    if c["parent_id"] == p_id:
                        meta = c.get("metadata", {})
                        if meta:
                            if "page" in meta:
                                pages.append(meta["page"])
                            if "start_time" in meta:
                                start_times.append(meta["start_time"])

                retrieved_parent_chunks.append(
                    {
                        "id": p_id,
                        "text": p_text,
                        "score": p_rec["score"],
                        "pages": sorted(list(set(pages))),
                        "start_times": sorted(list(set(start_times))),
                    }
                )

    context_str = "\n".join(context_parts)

    # Check for empty context in strict mode vs default mode
    if mode in ["strict", "default"]:
        if len(retrieved_parent_chunks) == 0:
            if mode == "strict":
                refusal_msg = "I couldn't find information about this in your documents. In Strict mode, answers are strictly limited to your uploaded sources. Try rephrasing your question or switch to Default mode."
                return "", routing_mode, retrieved_child_chunks, [], [], refusal_msg
            elif mode == "default":
                logger.info(
                    "No relevant context found in default mode — generating response using general AI knowledge."
                )
                general_prompt = f"""You are a helpful AI assistant. Answer the following question accurately, clearly, and concisely using your general knowledge.

Format your response using professional Markdown:
1. Use bold text to highlight key concepts, terms, or actions.
2. Use bulleted lists for unordered points, and numbered lists for sequences or steps.

Question:
{question}

Answer:"""
                if history:
                    history_str = "\n".join(
                        f"{h.get('role', 'user').capitalize()}: {h.get('content', '')}"
                        for h in history[-5:]
                    )
                    general_prompt = f"Chat History:\n{history_str}\n\n" + general_prompt

                return general_prompt, routing_mode, retrieved_child_chunks, [], [], None

    # 4. Load Custom Workspace Instructions
    instructions = ""
    metadata_file = workspace_dir / "metadata.json"
    if metadata_file.exists():
        try:
            with open(metadata_file, "r") as f:
                meta_data = json.load(f)
                instructions = meta_data.get("instructions", "").strip()
        except Exception as e:
            logger.error(
                f"Failed to read instructions from metadata for {workspace_id}: {e}"
            )

    # Inject workspace instructions if present
    if instructions:
        system_prompt = (
            f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n"
            + system_prompt
        )
        instruction_block = f"\nCRITICAL CUSTOM INSTRUCTION (Apply this strictly to your answer): {instructions}\n"
        system_prompt = system_prompt.replace(
            "Answer:", f"{instruction_block}\nAnswer:"
        )

    prompt = system_prompt.format(context=context_str, question=question)
    if history:
        history_str = ""
        for turn in history[-4:]:
            role = "User" if turn.get("role") == "user" else "Assistant"
            content = turn.get("content", "").strip()
            history_str += f"{role}: {content}\n"
        if history_str:
            prompt = f"Previous Conversation History:\n{history_str}\n\n{prompt}"

    set_cached_rag_prompt(
        workspace_id,
        question,
        model_name,
        mode,
        similarity_threshold,
        history,
        prompt,
        routing_mode,
        retrieved_child_chunks,
        retrieved_parent_chunks,
        parent_ids_used,
        refusal_msg,
    )
    return (
        prompt,
        routing_mode,
        retrieved_child_chunks,
        retrieved_parent_chunks,
        parent_ids_used,
        refusal_msg,
    )


async def retrieve_and_generate(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """
    Executes RAG and generates answer asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)

    MAX_TOKENS_BY_MODE = {"strict": 2000, "default": 2500, "explore": 0}
    max_parent_tokens = MAX_TOKENS_BY_MODE.get(mode, 2000)

    if mode == "explore":
        # Bypassing RAG entirely for Creative Mode
        instructions = ""
        workspace_dir = settings.workspaces_dir / workspace_id
        metadata_file = workspace_dir / "metadata.json"
        if metadata_file.exists():
            try:
                with open(metadata_file, "r") as f:
                    meta_data = json.load(f)
                    instructions = meta_data.get("instructions", "").strip()
            except Exception as e:
                logger.error(
                    f"Failed to read instructions from metadata for {workspace_id}: {e}"
                )

        system_prompt = "You are a brilliant general-purpose AI assistant. Answer the user's question using your pre-trained general knowledge. Give thorough, structured answers using markdown.\nFor factual claims, indicate if uncertain: add *(unverified)* qualifier.\nRespond in the same language as the user's question.\nFormat answers with headers, bullets, and code blocks where appropriate.\nDo not mention or cite any document chunks or source files."
        if instructions:
            system_prompt = (
                f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n"
                + system_prompt
            )

        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

        # Rough estimate: 1 token ≈ 4 chars
        estimated_tokens = len(prompt) // 4
        logger.info(
            f"[{mode.upper()} MODE] Estimated tokens in prompt: ~{estimated_tokens}"
        )

        base_url = ollama_url if ollama_url else settings.ollama_base_url
        url = f"{base_url}/api/generate"
        payload = {
            "model": model_name,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": temperature if temperature is not None else 0.7,
                "num_thread": max(1, multiprocessing.cpu_count() // 2),
                "num_ctx": settings.ollama_num_ctx,
            },
        }

        raw_answer = ""
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=5.0)) as client:
                response = await _call_ollama_with_retry(
                    client, "POST", url, json=payload
                )
                if response.status_code == 200:
                    result = response.json()
                    raw_answer = result.get("response", "").strip()
                else:
                    raw_answer = (
                        f"Error: Ollama returned status code {response.status_code}"
                    )
        except Exception as e:
            raw_answer = f"Error calling Ollama API: {e}"

        return {
            "question": original_question,
            "answer": raw_answer,
            "plain_answer": raw_answer,
            "citations": [],
            "child_ids": [],
            "parent_ids": [],
            "retrieved_child_chunks": [],
            "retrieved_parent_chunks": [],
            "routing_mode": "EXPLORE",
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": [],
        }

    try:
        (
            prompt,
            routing_mode,
            retrieved_child_chunks,
            retrieved_parent_chunks,
            parent_ids_used,
            refusal_msg,
        ) = _prepare_rag_prompt(
            workspace_id,
            question,
            model_name=model_name,
            max_parent_tokens=max_parent_tokens,
            mode=mode,
            similarity_threshold=similarity_threshold,
            history=history,
        )
    except FileNotFoundError as fnf:
        return {
            "question": original_question,
            "answer": str(fnf),
            "plain_answer": str(fnf),
            "citations": [],
            "child_ids": [],
            "parent_ids": [],
            "retrieved_child_chunks": [],
            "retrieved_parent_chunks": [],
            "routing_mode": "ERROR",
            "latency_ms": int((time.time() - t_start) * 1000),
        }
    except Exception as e:
        logger.error(f"Error preparing prompt: {e}", exc_info=True)
        return {
            "question": original_question,
            "answer": f"Error preparing prompt: {e}",
            "plain_answer": f"Error preparing prompt: {e}",
            "citations": [],
            "child_ids": [],
            "parent_ids": [],
            "retrieved_child_chunks": [],
            "retrieved_parent_chunks": [],
            "routing_mode": "ERROR",
            "latency_ms": int((time.time() - t_start) * 1000),
        }

    if refusal_msg:
        return {
            "question": original_question,
            "answer": refusal_msg,
            "plain_answer": refusal_msg,
            "citations": [],
            "child_ids": [c["id"] for c in retrieved_child_chunks],
            "parent_ids": parent_ids_used,
            "retrieved_child_chunks": retrieved_child_chunks,
            "retrieved_parent_chunks": retrieved_parent_chunks,
            "routing_mode": routing_mode,
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": [],
        }

    if not prompt and mode == "explore":
        # We need to recreate the prompt since it fell back from default
        system_prompt = "You are a brilliant general-purpose AI assistant. Answer the user's question using your pre-trained general knowledge. Give thorough, structured answers using markdown.\nFor factual claims, indicate if uncertain: add *(unverified)* qualifier.\nRespond in the same language as the user's question.\nFormat answers with headers, bullets, and code blocks where appropriate.\nDo not mention or cite any document chunks or source files."
        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

    # Rough estimate: 1 token ≈ 4 chars
    estimated_tokens = len(prompt) // 4
    logger.info(
        f"[{mode.upper()} MODE] Estimated tokens in prompt: ~{estimated_tokens}"
    )

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": temperature if temperature is not None else 0.0,
            "num_thread": max(1, multiprocessing.cpu_count() // 2),
            "num_ctx": settings.ollama_num_ctx,
        },
    }

    raw_answer = ""
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=5.0)) as client:
            response = await _call_ollama_with_retry(client, "POST", url, json=payload)
            if response.status_code == 200:
                result = response.json()
                raw_answer = result.get("response", "").strip()
            else:
                raw_answer = (
                    f"Error: Ollama returned status code {response.status_code}"
                )
    except Exception as e:
        raw_answer = f"Error calling Ollama API: {e}"

    # Load sources to get source names for citation metadata
    source_id_to_name, source_id_to_url = _load_source_maps(workspace_id)

    # 5. Claim Sanitization
    answer_footnoted, citations_meta, answer_plain = sanitize_response(
        raw_answer,
        parent_chunks=retrieved_parent_chunks,
        source_id_to_name=source_id_to_name,
        source_id_to_url=source_id_to_url,
    )
    latency_ms = int((time.time() - t_start) * 1000)

    return {
        "question": original_question,
        "answer": answer_footnoted,
        "plain_answer": answer_plain,
        "citations": citations_meta,
        "child_ids": [c["id"] for c in retrieved_child_chunks],
        "parent_ids": parent_ids_used,
        "retrieved_child_chunks": retrieved_child_chunks,
        "retrieved_parent_chunks": retrieved_parent_chunks,
        "routing_mode": routing_mode,
        "latency_ms": latency_ms,
        "recommended_questions": [],
    }


async def retrieve_and_generate_stream(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
):
    """
    Executes RAG and yields Server-Sent Events (SSE) token chunks asynchronously.
    """
    yield ': heartbeat\n\n'
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)

    MAX_TOKENS_BY_MODE = {"strict": 2000, "default": 2500, "explore": 0}
    max_parent_tokens = MAX_TOKENS_BY_MODE.get(mode, 2000)

    if mode == "explore":
        # Bypassing RAG entirely for Creative Mode
        instructions = ""
        workspace_dir = settings.workspaces_dir / workspace_id
        metadata_file = workspace_dir / "metadata.json"
        if metadata_file.exists():
            try:
                with open(metadata_file, "r") as f:
                    meta_data = json.load(f)
                    instructions = meta_data.get("instructions", "").strip()
            except Exception as e:
                logger.error(
                    f"Failed to read instructions from metadata for {workspace_id}: {e}"
                )

        system_prompt = "You are a brilliant general-purpose AI assistant. Answer the user's question using your pre-trained general knowledge. Give thorough, structured answers using markdown.\nFor factual claims, indicate if uncertain: add *(unverified)* qualifier.\nRespond in the same language as the user's question.\nFormat answers with headers, bullets, and code blocks where appropriate.\nDo not mention or cite any document chunks or source files."
        if instructions:
            system_prompt = (
                f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n"
                + system_prompt
            )

        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

        # Rough estimate: 1 token ≈ 4 chars
        estimated_tokens = len(prompt) // 4
        logger.info(
            f"[{mode.upper()} MODE] Estimated tokens in prompt: ~{estimated_tokens}"
        )

        base_url = ollama_url if ollama_url else settings.ollama_base_url
        url = f"{base_url}/api/generate"
        payload = {
            "model": model_name,
            "prompt": prompt,
            "stream": True,
            "options": {
                "temperature": temperature if temperature is not None else 0.7,
                "num_thread": max(1, multiprocessing.cpu_count() // 2),
                "num_ctx": settings.ollama_num_ctx,
            },
        }

        full_text_buffer = ""
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=5.0)) as client:
                async with client.stream("POST", url, json=payload) as response:
                    if response.status_code != 200:
                        yield f"data: {json.dumps({'token': f'Error: Ollama returned status {response.status_code}', 'done': True, 'error': True})}\n\n"
                        return
                    async for line in response.aiter_lines():
                        if line:
                            data = json.loads(line)
                            token = data.get("response", "")
                            yield f"data: {json.dumps({'token': token, 'done': False})}\n\n"
                            full_text_buffer += token
        except httpx.ConnectError:
            yield "data: [ERROR] Ollama is not running. Please start Ollama and try again.\n\n"
            return
        except httpx.TimeoutException:
            yield "data: [ERROR] The AI engine timed out. Please try a shorter question or restart Ollama.\n\n"
            return
        except Exception as e:
            logger.error(f"Unexpected error during streaming: {e}")
            yield f"data: [ERROR] An unexpected error occurred: {str(e)[:100]}\n\n"
            return

        latency_ms = int((time.time() - t_start) * 1000)
        yield f"data: {json.dumps({'done': True, 'answer': full_text_buffer.strip(), 'plain_answer': full_text_buffer.strip(), 'citations': [], 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"
        return

    try:
        (
            prompt,
            routing_mode,
            retrieved_child_chunks,
            retrieved_parent_chunks,
            parent_ids_used,
            refusal_msg,
        ) = _prepare_rag_prompt(
            workspace_id,
            question,
            model_name=model_name,
            max_parent_tokens=max_parent_tokens,
            mode=mode,
            similarity_threshold=similarity_threshold,
            history=history,
        )
    except FileNotFoundError as fnf:
        yield f"data: {json.dumps({'token': str(fnf), 'done': True, 'error': True})}\n\n"
        return
    except Exception as e:
        yield f"data: {json.dumps({'token': f'Error preparing prompt: {e}', 'done': True, 'error': True})}\n\n"
        return

    if refusal_msg:
        words = refusal_msg.split(" ")
        for i, w in enumerate(words):
            chunk = (w + " ") if i < len(words) - 1 else w
            yield f"data: {json.dumps({'token': chunk, 'done': False})}\n\n"
            await asyncio.sleep(0.01)
        yield f"data: {json.dumps({'done': True, 'answer': refusal_msg, 'plain_answer': refusal_msg, 'citations': [], 'recommended_questions': [], 'latency_ms': int((time.time() - t_start) * 1000)})}\n\n"
        return

    if not prompt and mode == "explore":
        # We need to recreate the prompt since it fell back from default
        system_prompt = "You are a brilliant general-purpose AI assistant. Answer the user's question using your pre-trained general knowledge. Give thorough, structured answers using markdown.\nFor factual claims, indicate if uncertain: add *(unverified)* qualifier.\nRespond in the same language as the user's question.\nFormat answers with headers, bullets, and code blocks where appropriate.\nDo not mention or cite any document chunks or source files."
        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

    # Rough estimate: 1 token ≈ 4 chars
    estimated_tokens = len(prompt) // 4
    logger.info(
        f"[{mode.upper()} MODE] Estimated tokens in prompt: ~{estimated_tokens}"
    )

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": True,
        "options": {
            "temperature": temperature if temperature is not None else 0.0,
            "num_thread": max(1, multiprocessing.cpu_count() // 2),
            "num_ctx": settings.ollama_num_ctx,
        },
    }

    full_text_buffer = ""
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=5.0)) as client:
            async with client.stream("POST", url, json=payload) as response:
                if response.status_code != 200:
                    yield f"data: {json.dumps({'token': f'Error: Ollama returned status {response.status_code}', 'done': True, 'error': True})}\n\n"
                    return
                async for line in response.aiter_lines():
                    if line:
                        data = json.loads(line)
                        token = data.get("response", "")
                        yield f"data: {json.dumps({'token': token, 'done': False})}\n\n"
                        full_text_buffer += token
    except httpx.ConnectError:
        yield "data: [ERROR] Ollama is not running. Please start Ollama and try again.\n\n"
        return
    except httpx.TimeoutException:
        yield "data: [ERROR] The AI engine timed out. Please try a shorter question or restart Ollama.\n\n"
        return
    except Exception as e:
        logger.error(f"Unexpected error during streaming: {e}")
        yield f"data: [ERROR] An unexpected error occurred: {str(e)[:100]}\n\n"
        return

    # Load source names for citation mapping
    source_id_to_name, source_id_to_url = _load_source_maps(workspace_id)

    answer_footnoted, citations_meta, answer_plain = sanitize_response(
        full_text_buffer.strip(),
        parent_chunks=retrieved_parent_chunks,
        source_id_to_name=source_id_to_name,
        source_id_to_url=source_id_to_url,
    )
    latency_ms = int((time.time() - t_start) * 1000)

    # Yield the final control message with all citations and followups
    yield f"data: {json.dumps({'done': True, 'answer': answer_footnoted, 'plain_answer': answer_plain, 'citations': citations_meta, 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"


def _prepare_universal_rag_prompt(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    similarity_threshold: Optional[float] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Tuple[
    str,
    str,
    List[Dict[str, Any]],
    List[Dict[str, Any]],
    List[str],
    Optional[str],
    Dict[str, str],
]:
    refusal_msg = None
    is_global_summary = bool(GLOBAL_SUMMARY_REGEX.search(question))
    routing_mode = "GLOBAL_SUMMARY" if is_global_summary else "STANDARD_QA"
    k = 4  # Top-K child chunks per workspace to fetch

    is_meta_retrieval = False
    if not is_global_summary and INTENT_REGEX.search(question):
        routing_mode = "META_RETRIEVAL"
        k = 8
        is_meta_retrieval = True

    system_prompt = get_adaptive_system_prompts(
        model_name, mode, is_meta_retrieval=is_meta_retrieval
    )

    logger.info(
        f"Universal Question routed to {routing_mode} (per-workspace Top-K={k}), mode={mode}"
    )

    all_child_chunks = []
    workspace_names = {}
    source_id_to_name = {}
    source_id_to_url = {}
    workspace_instructions = []

    # First load workspace names and instructions
    for ws_id in workspace_ids:
        workspace_dir = settings.workspaces_dir / ws_id
        metadata_file = workspace_dir / "metadata.json"

        ws_name = ws_id
        if metadata_file.exists():
            try:
                with open(metadata_file, "r") as f:
                    meta_data = json.load(f)
                    ws_name = meta_data.get("name", ws_id)
                    inst = meta_data.get("instructions", "").strip()
                    if inst:
                        workspace_instructions.append(
                            f"Workspace '{ws_name}' Instructions: {inst}"
                        )
            except Exception as e:
                logger.error(f"Failed to read metadata for workspace {ws_id}: {e}")
        workspace_names[ws_id] = ws_name

    context_parts = []
    retrieved_parent_chunks = []
    parent_ids_used = []

    if is_global_summary:
        from app.core.database import get_all_parent_chunks_ordered

        current_tokens = 0
        for ws_id in workspace_ids:
            ws_name = workspace_names.get(ws_id, ws_id)
            try:
                db_parents = get_all_parent_chunks_ordered(ws_id)
            except Exception as e:
                logger.error(
                    f"Error loading sequential parent chunks for universal workspace {ws_id}: {e}"
                )
                db_parents = []

            for p in db_parents:
                p_text = p["text"]
                p_tokens = estimate_tokens(p_text)
                if current_tokens + p_tokens > max_parent_tokens:
                    logger.info(
                        f"Universal parent chunk {p['id']} excluded due to budget."
                    )
                    continue
                current_tokens += p_tokens
                context_parts.append(
                    f'<chunk id="{p["id"]}" workspace="{ws_name}">\n{p_text}\n</chunk>'
                )
                parent_ids_used.append(p["id"])
                retrieved_parent_chunks.append(
                    {
                        "id": p["id"],
                        "text": p_text,
                        "score": 1.0,
                        "workspace_id": ws_id,
                        "workspace_name": ws_name,
                    }
                )
    else:
        # Generate query embedding
        model = get_embedding_model()
        query_emb = model.encode([question], normalize_embeddings=True)[0]
        query_contiguous = query_emb.copy().astype(np.float32)
        # Loop over all requested workspace IDs for vector search
        for ws_id in workspace_ids:
            workspace_dir = settings.workspaces_dir / ws_id

            try:
                index = get_cached_usearch_index(ws_id, workspace_dir)
                results = index.search(query_contiguous, k)
                scores = [[1.0 - d for d in results.distances]]
                indices = [results.keys]
                valid_indices = [int(idx) for idx in indices[0] if idx >= 0]

                if not valid_indices:
                    continue

                from app.core.database import get_child_chunks_by_global_indices

                db_chunks = get_child_chunks_by_global_indices(ws_id, valid_indices)
                chunks_by_global_idx = {c["global_vector_index"]: c for c in db_chunks}

                for rank, (score, chunk_idx) in enumerate(
                    zip(scores[0], indices[0]), 1
                ):
                    chunk_idx_int = int(chunk_idx)
                    if chunk_idx_int in chunks_by_global_idx:
                        c_chunk = chunks_by_global_idx[chunk_idx_int]
                        all_child_chunks.append(
                            {
                                "workspace_id": ws_id,
                                "workspace_name": workspace_names.get(ws_id, ws_id),
                                "rank_local": rank,
                                "score": float(score),
                                "id": c_chunk["id"],
                                "text": c_chunk["text"],
                                "parent_id": c_chunk["parent_id"],
                                "metadata": c_chunk.get("metadata", {}),
                            }
                        )

                from app.api.routes.sources import load_sources

                try:
                    sources = load_sources(ws_id)
                    for s in sources:
                        source_id_to_name[s.id] = (
                            f"{workspace_names.get(ws_id, ws_id)} > {s.name}"
                        )
                        if s.url:
                            source_id_to_url[s.id] = s.url
                except Exception:
                    pass

            except Exception as e:
                logger.error(
                    f"Error performing vector search in workspace {ws_id}: {e}"
                )

        all_child_chunks.sort(key=lambda x: x["score"], reverse=True)

        threshold = similarity_threshold if similarity_threshold is not None else 0.25
        if mode in ["strict", "default"]:
            if len(all_child_chunks) == 0 or all_child_chunks[0]["score"] < threshold:
                refusal_msg = "This topic is not present in the uploaded sources. Try turning off Strict Source Mode to search using general AI knowledge."
                return "", routing_mode, [], [], [], refusal_msg, source_id_to_name

        parent_records = []
        parent_keys_seen = set()

        for c in all_child_chunks:
            parent_id = c["parent_id"]
            ws_id = c["workspace_id"]
            if parent_id is not None:
                key = f"{ws_id}_{parent_id}"
                if key not in parent_keys_seen:
                    parent_keys_seen.add(key)
                    parent_records.append(
                        {
                            "score": c["score"],
                            "parent_id": parent_id,
                            "workspace_id": ws_id,
                            "workspace_name": c["workspace_name"],
                        }
                    )

        parent_records.sort(key=lambda x: x["score"], reverse=True)

        from app.core.database import get_parent_chunks_by_ids

        parents_by_workspace_and_id = {}

        for ws_id in workspace_ids:
            ws_parent_ids = [
                r["parent_id"] for r in parent_records if r["workspace_id"] == ws_id
            ]
            if ws_parent_ids:
                try:
                    db_parents = get_parent_chunks_by_ids(ws_id, ws_parent_ids)
                    parents_by_workspace_and_id[ws_id] = {
                        p["id"]: p["text"] for p in db_parents
                    }
                except Exception as e:
                    logger.error(
                        f"Failed to load parent chunks for workspace {ws_id}: {e}"
                    )

        current_tokens = 0
        for p_rec in parent_records:
            ws_id = p_rec["workspace_id"]
            p_id = p_rec["parent_id"]
            ws_name = p_rec["workspace_name"]

            ws_parents = parents_by_workspace_and_id.get(ws_id, {})
            if p_id in ws_parents:
                p_text = ws_parents[p_id]
                p_tokens = estimate_tokens(p_text)

                if current_tokens + p_tokens > max_parent_tokens:
                    logger.info(
                        f"Parent chunk {p_id} from {ws_name} excluded due to budget."
                    )
                    continue

                current_tokens += p_tokens
                context_parts.append(
                    f'<chunk id="{p_id}" workspace="{ws_name}">\n{p_text}\n</chunk>'
                )
                parent_ids_used.append(p_id)
                pages = []
                start_times = []
                for c in all_child_chunks:
                    if c["workspace_id"] == ws_id and c["parent_id"] == p_id:
                        meta = c.get("metadata", {})
                        if meta:
                            if "page" in meta:
                                pages.append(meta["page"])
                            if "start_time" in meta:
                                start_times.append(meta["start_time"])

                retrieved_parent_chunks.append(
                    {
                        "id": p_id,
                        "text": p_text,
                        "score": p_rec["score"],
                        "workspace_id": ws_id,
                        "workspace_name": ws_name,
                        "pages": sorted(list(set(pages))),
                        "start_times": sorted(list(set(start_times))),
                    }
                )

    context_str = "\n".join(context_parts)

    if mode in ["strict", "default"]:
        if len(retrieved_parent_chunks) == 0:
            refusal_msg = "This topic is not present in the uploaded sources. Try turning off Strict Source Mode to search using general AI knowledge."
            return (
                "",
                routing_mode,
                all_child_chunks,
                [],
                [],
                refusal_msg,
                source_id_to_name,
                source_id_to_url,
            )

    instructions = "\n".join(workspace_instructions).strip()
    if instructions:
        system_prompt = (
            f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions}\n\n"
            + system_prompt
        )
        instruction_block = f"\nCRITICAL CUSTOM INSTRUCTION (Apply this strictly to your answer): {instructions}\n"
        system_prompt = system_prompt.replace(
            "Answer:", f"{instruction_block}\nAnswer:"
        )

    prompt = system_prompt.format(context=context_str, question=question)
    if history:
        history_str = ""
        for turn in history[-4:]:
            role = "User" if turn.get("role") == "user" else "Assistant"
            content = turn.get("content", "").strip()
            history_str += f"{role}: {content}\n"
        if history_str:
            prompt = f"Previous Conversation History:\n{history_str}\n\n{prompt}"

    return (
        prompt,
        routing_mode,
        all_child_chunks,
        retrieved_parent_chunks,
        parent_ids_used,
        refusal_msg,
        source_id_to_name,
        source_id_to_url,
    )


async def retrieve_and_generate_universal(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """
    Executes RAG across multiple workspaces and generates answer asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)

    if mode == "explore":
        # Bypassing RAG entirely for Creative Mode
        workspace_instructions = []
        for ws_id in workspace_ids:
            workspace_dir = settings.workspaces_dir / ws_id
            metadata_file = workspace_dir / "metadata.json"
            if metadata_file.exists():
                try:
                    with open(metadata_file, "r") as f:
                        meta_data = json.load(f)
                        ws_name = meta_data.get("name", ws_id)
                        inst = meta_data.get("instructions", "").strip()
                        if inst:
                            workspace_instructions.append(
                                f"Workspace '{ws_name}' Instructions: {inst}"
                            )
                except Exception as e:
                    logger.error(f"Failed to read metadata for workspace {ws_id}: {e}")

        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if workspace_instructions:
            instructions_str = "\n".join(workspace_instructions).strip()
            system_prompt = (
                f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions_str}\n\n"
                + system_prompt
            )

        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

        base_url = ollama_url if ollama_url else settings.ollama_base_url
        url = f"{base_url}/api/generate"
        payload = {
            "model": model_name,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": temperature if temperature is not None else 0.7,
                "num_thread": max(1, multiprocessing.cpu_count() // 2),
                "num_ctx": settings.ollama_num_ctx,
            },
        }

        raw_answer = ""
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=5.0)) as client:
                response = await _call_ollama_with_retry(
                    client, "POST", url, json=payload
                )
                if response.status_code == 200:
                    result = response.json()
                    raw_answer = result.get("response", "").strip()
                else:
                    raw_answer = (
                        f"Error: Ollama returned status code {response.status_code}"
                    )
        except Exception as e:
            raw_answer = f"Error calling Ollama API: {e}"

        return {
            "question": original_question,
            "answer": raw_answer,
            "plain_answer": raw_answer,
            "citations": [],
            "child_ids": [],
            "parent_ids": [],
            "retrieved_child_chunks": [],
            "retrieved_parent_chunks": [],
            "routing_mode": "EXPLORE",
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": [],
        }

    try:
        (
            prompt,
            routing_mode,
            retrieved_child_chunks,
            retrieved_parent_chunks,
            parent_ids_used,
            refusal_msg,
            source_id_to_name,
            source_id_to_url,
        ) = _prepare_universal_rag_prompt(
            workspace_ids,
            question,
            model_name=model_name,
            max_parent_tokens=max_parent_tokens,
            mode=mode,
            similarity_threshold=similarity_threshold,
            history=history,
        )
    except Exception as e:
        err_msg = f"Universal RAG failed: {e}"
        return {
            "question": original_question,
            "answer": err_msg,
            "plain_answer": err_msg,
            "citations": [],
            "child_ids": [],
            "parent_ids": [],
            "retrieved_child_chunks": [],
            "retrieved_parent_chunks": [],
            "routing_mode": "ERROR",
            "latency_ms": int((time.time() - t_start) * 1000),
        }

    if refusal_msg:
        return {
            "question": original_question,
            "answer": refusal_msg,
            "plain_answer": refusal_msg,
            "citations": [],
            "child_ids": [c["id"] for c in retrieved_child_chunks],
            "parent_ids": parent_ids_used,
            "retrieved_child_chunks": retrieved_child_chunks,
            "retrieved_parent_chunks": retrieved_parent_chunks,
            "routing_mode": routing_mode,
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": [],
        }

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": temperature if temperature is not None else 0.0,
            "num_thread": max(1, multiprocessing.cpu_count() // 2),
            "num_ctx": settings.ollama_num_ctx,
        },
    }

    raw_answer = ""
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(90.0, connect=5.0)) as client:
            response = await _call_ollama_with_retry(client, "POST", url, json=payload)
            if response.status_code == 200:
                result = response.json()
                raw_answer = result.get("response", "").strip()
            else:
                raw_answer = (
                    f"Error: Ollama returned status code {response.status_code}"
                )
    except Exception as e:
        raw_answer = f"Error calling Ollama API: {e}"

    # Claim Sanitization
    answer_footnoted, citations_meta, answer_plain = sanitize_response(
        raw_answer,
        parent_chunks=retrieved_parent_chunks,
        source_id_to_name=source_id_to_name,
        source_id_to_url=source_id_to_url,
    )
    latency_ms = int((time.time() - t_start) * 1000)

    return {
        "question": original_question,
        "answer": answer_footnoted,
        "plain_answer": answer_plain,
        "citations": citations_meta,
        "child_ids": [c["id"] for c in retrieved_child_chunks],
        "parent_ids": parent_ids_used,
        "retrieved_child_chunks": retrieved_child_chunks,
        "retrieved_parent_chunks": retrieved_parent_chunks,
        "routing_mode": routing_mode,
        "latency_ms": latency_ms,
        "recommended_questions": [],
    }


async def retrieve_and_generate_universal_stream(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    mode: str = "default",
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None,
):
    """
    Executes universal RAG and yields Server-Sent Events (SSE) token chunks asynchronously.
    """
    yield ': heartbeat\n\n'
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)

    if mode == "explore":
        # Bypassing RAG entirely for Creative Mode
        workspace_instructions = []
        for ws_id in workspace_ids:
            workspace_dir = settings.workspaces_dir / ws_id
            metadata_file = workspace_dir / "metadata.json"
            if metadata_file.exists():
                try:
                    with open(metadata_file, "r") as f:
                        meta_data = json.load(f)
                        ws_name = meta_data.get("name", ws_id)
                        inst = meta_data.get("instructions", "").strip()
                        if inst:
                            workspace_instructions.append(
                                f"Workspace '{ws_name}' Instructions: {inst}"
                            )
                except Exception as e:
                    logger.error(f"Failed to read metadata for workspace {ws_id}: {e}")

        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if workspace_instructions:
            instructions_str = "\n".join(workspace_instructions).strip()
            system_prompt = (
                f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions_str}\n\n"
                + system_prompt
            )

        prompt = f"{system_prompt}\n\nQuestion:\n{question}\n\nAnswer:"

        base_url = ollama_url if ollama_url else settings.ollama_base_url
        url = f"{base_url}/api/generate"
        payload = {
            "model": model_name,
            "prompt": prompt,
            "stream": True,
            "options": {
                "temperature": temperature if temperature is not None else 0.7,
                "num_thread": max(1, multiprocessing.cpu_count() // 2),
                "num_ctx": settings.ollama_num_ctx,
            },
        }

        full_text_buffer = ""
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=5.0)) as client:
                async with client.stream("POST", url, json=payload) as response:
                    if response.status_code != 200:
                        yield f"data: {json.dumps({'token': f'Error: Ollama returned status {response.status_code}', 'done': True, 'error': True})}\n\n"
                        return
                    async for line in response.aiter_lines():
                        if line:
                            data = json.loads(line)
                            token = data.get("response", "")
                            yield f"data: {json.dumps({'token': token, 'done': False})}\n\n"
                            full_text_buffer += token
        except httpx.ConnectError:
            yield "data: [ERROR] Ollama is not running. Please start Ollama and try again.\n\n"
            return
        except httpx.TimeoutException:
            yield "data: [ERROR] The AI engine timed out. Please try a shorter question or restart Ollama.\n\n"
            return
        except Exception as e:
            logger.error(f"Unexpected error during streaming: {e}")
            yield f"data: [ERROR] An unexpected error occurred: {str(e)[:100]}\n\n"
            return

        latency_ms = int((time.time() - t_start) * 1000)
        yield f"data: {json.dumps({'done': True, 'answer': full_text_buffer.strip(), 'plain_answer': full_text_buffer.strip(), 'citations': [], 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"
        return

    try:
        (
            prompt,
            routing_mode,
            retrieved_child_chunks,
            retrieved_parent_chunks,
            parent_ids_used,
            refusal_msg,
            source_id_to_name,
            source_id_to_url,
        ) = _prepare_universal_rag_prompt(
            workspace_ids,
            question,
            model_name=model_name,
            max_parent_tokens=max_parent_tokens,
            mode=mode,
            similarity_threshold=similarity_threshold,
            history=history,
        )
    except Exception as e:
        yield f"data: {json.dumps({'token': f'Error preparing prompt: {e}', 'done': True, 'error': True})}\n\n"
        return

    if refusal_msg:
        words = refusal_msg.split(" ")
        for i, w in enumerate(words):
            chunk = (w + " ") if i < len(words) - 1 else w
            yield f"data: {json.dumps({'token': chunk, 'done': False})}\n\n"
            await asyncio.sleep(0.01)
        yield f"data: {json.dumps({'done': True, 'answer': refusal_msg, 'plain_answer': refusal_msg, 'citations': [], 'recommended_questions': [], 'latency_ms': int((time.time() - t_start) * 1000)})}\n\n"
        return

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": True,
        "options": {
            "temperature": temperature if temperature is not None else 0.0,
            "num_thread": max(1, multiprocessing.cpu_count() // 2),
            "num_ctx": settings.ollama_num_ctx,
        },
    }

    full_text_buffer = ""
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=5.0)) as client:
            async with client.stream("POST", url, json=payload) as response:
                if response.status_code != 200:
                    yield f"data: {json.dumps({'token': f'Error: Ollama returned status {response.status_code}', 'done': True, 'error': True})}\n\n"
                    return
                async for line in response.aiter_lines():
                    if line:
                        data = json.loads(line)
                        token = data.get("response", "")
                        yield f"data: {json.dumps({'token': token, 'done': False})}\n\n"
                        full_text_buffer += token
    except httpx.ConnectError:
        yield "data: [ERROR] Ollama is not running. Please start Ollama and try again.\n\n"
        return
    except httpx.TimeoutException:
        yield "data: [ERROR] The AI engine timed out. Please try a shorter question or restart Ollama.\n\n"
        return
    except Exception as e:
        logger.error(f"Unexpected error during streaming: {e}")
        yield f"data: [ERROR] An unexpected error occurred: {str(e)[:100]}\n\n"
        return

    answer_footnoted, citations_meta, answer_plain = sanitize_response(
        full_text_buffer.strip(),
        parent_chunks=retrieved_parent_chunks,
        source_id_to_name=source_id_to_name,
        source_id_to_url=source_id_to_url,
    )
    latency_ms = int((time.time() - t_start) * 1000)

    yield f"data: {json.dumps({'done': True, 'answer': answer_footnoted, 'plain_answer': answer_plain, 'citations': citations_meta, 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"
