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

def _get_or_build_usearch_index(workspace_id: str, workspace_dir: Path) -> Index:
    usearch_file = workspace_dir / "index.usearch"
    faiss_file = workspace_dir / "index.faiss"
    
    if not usearch_file.exists():
        sources_file = workspace_dir / "sources.json"
        if faiss_file.exists() or sources_file.exists():
            logger.info(f"index.usearch not found for workspace {workspace_id}, but legacy/source files exist. Recompiling usearch index...")
            from app.core.processors.vector_db import VectorDBProcessor
            try:
                processor = VectorDBProcessor()
                processor.process(workspace_id)
            except Exception as e:
                logger.error(f"Failed to auto-recompile usearch index for workspace {workspace_id}: {e}")
                
    if not usearch_file.exists():
        raise FileNotFoundError(f"Knowledge base index is not compiled for workspace {workspace_id}. Please process your sources first.")
        
    index = Index(ndim=768, metric="cos")
    index.load(str(usearch_file))
    return index
import asyncio
import multiprocessing

from app.core.config import settings
from app.core.processors.embeddings import get_embedding_model

logger = logging.getLogger("kivo.core.retriever")

# Broad retrieval keywords regex
INTENT_REGEX = re.compile(
    r"\b(list\s+every|find\s+all|retrieve\s+all|timeline\s+of|summarize\s+references\s+to|discuss\s+all|retrieve\s+every|find\s+content\s+connected\s+to|find\s+every|retrieve\s+information|retrieve\s+content)\b",
    re.IGNORECASE
)

GLOBAL_SUMMARY_REGEX = re.compile(
    r"\b(what\s+is\s+the\s+video\s+about|what\s+is\s+this\s+video\s+about|what\s+is\s+the\s+document\s+about|what\s+is\s+this\s+document\s+about|what\s+is\s+the\s+file\s+about|what\s+is\s+this\s+file\s+about|summarize|summary|overview|what\s+is\s+this\s+about|what\s+are\s+these\s+documents\s+about|what\s+does\s+this\s+talk\s+about|what\s+is\s+the\s+content\s+of|give\s+me\s+a\s+summary|explain\s+the\s+entire|main\s+idea|main\s+theme|what\s+are\s+the\s+key\s+takeaways)\b",
    re.IGNORECASE
)

# Token estimation helper
def estimate_tokens(text: str) -> int:
    return int(len(text.split()) * 1.3)

STRICT_QA_PROMPT = """You are a grounded QA assistant. Answer the user's question using the provided context chunks as your primary source of facts and references.
Synthesize the provided context chunks to construct a helpful, accurate, and comprehensive response.
Prioritize the facts present in the context, but write in a natural, explanatory manner. Do not invent or make up facts that are not supported by the context.
If the context does not contain relevant information to answer the question, politely inform the user that the topic is not covered in the uploaded sources.

If the workspace system instructions specify a custom language (e.g. Hindi, French, Spanish, German, etc.) or formatting constraint, you MUST translate the facts from the context and write your entire response (including explanations and sentences) strictly in that requested language/format.

Format your response using professional Markdown. To make your response easy to read, visual, and well-structured:
1. Use bold text to highlight key concepts, terms, or actions.
2. Use bulleted lists for unordered points, and numbered lists for sequences or steps. Use lettered sub-bullets (a, b, c) if nesting is required.
3. Use tables when presenting comparative data, key-value pairs, or structured details.
4. Use code blocks with the appropriate language tag (e.g. ```bash, ```python, etc.) for commands, code snippets, or configuration.
5. Use italics for emphasis, definitions, or quotes.

For every factual claim you make, you MUST cite the chunk ID of the context where the information was found using the format [chunk_id] (where chunk_id is the exact id attribute of the retrieved <chunk> tag, e.g. if the tag is <chunk id="doc1_p4">, cite as [doc1_p4]). Never write placeholder IDs.

Context:
{context}

Question:
{question}

Answer:"""

CREATIVE_QA_PROMPT = """You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge.
Do not mention or cite any document chunks or source files.
Write your response in clean Markdown.

Question:
{question}

Answer:"""

META_RETRIEVAL_PROMPT = """You are a retrieval and synthesis assistant. The user is asking for a comprehensive list or summary of references across the entire knowledge base.
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

def get_adaptive_system_prompts(model_name: str, is_strict: bool, is_meta_retrieval: bool = False) -> str:
    """
    Returns an optimized system prompt depending on the model's capabilities and size.
    Prevents smaller or reasoning models from getting stuck or failing to format.
    """
    model_name_lower = model_name.lower()
    
    # 1. Identify model category
    is_reasoning_model = "r1" in model_name_lower or "reasoning" in model_name_lower or "o1" in model_name_lower
    is_small_model = any(kw in model_name_lower for kw in ["1.5b", "1b", "2b", "3b", "smollm", "tiny"])
    is_default_qwen = "qwen2.5:1.5b" in model_name_lower or "qwen2.5" in model_name_lower
    
    if is_reasoning_model:
        # Reasoning models output <think>...</think>. Keep prompt simple and direct.
        # Too many constraints cause reasoning models to loop or fail reasoning.
        if is_strict:
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
        if is_strict:
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
        if is_strict:
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
                return STRICT_QA_PROMPT
        else:
            return CREATIVE_QA_PROMPT

def sanitize_response(
    answer: str,
    source_id_to_name: Dict[str, str] = None,
    parent_chunks: List[Dict[str, Any]] = None,
    source_id_to_url: Dict[str, str] = None
) -> Tuple[str, List[Dict[str, Any]], str]:
    """
    Removes XML tags, maps raw citations like [source_id_p0] to sequential footnotes like [1], [2],
    and returns the clean answer with footnotes, the citations metadata, and a completely plain text answer (no citations).
    """
    if not answer or not isinstance(answer, str):
        return "", [], ""
        
    import re
    
    # 1. Remove XML tags like <chunk ...> and </chunk>
    answer_clean = re.sub(r'</?chunk[^>]*>', '', answer)
    
    # Find all raw citation tags like [uuid_p0], [chunk_id="uuid_p0"], etc.
    # Pattern captures group 1 as the clean chunk ID, while the full match is the entire bracketed tag.
    pattern = re.compile(r'\[[^\]]*?([a-zA-Z0-9_-]+_[pc]\d+)[^\]]*?\]')
    matches = list(pattern.finditer(answer_clean))
    
    unique_citations = []
    full_to_clean = {}
    for match in matches:
        full_tag = match.group(0)
        clean_id = match.group(1)
        full_to_clean[full_tag] = clean_id
        if clean_id not in unique_citations:
            unique_citations.append(clean_id)
            
    citations_meta = []
    answer_footnoted = answer_clean
    answer_plain = answer_clean
    
    for i, clean_id in enumerate(unique_citations, 1):
        # Extract source_id from composite citation id: source_id_pX or source_id_cX
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
        if parent_chunks:
            for p in parent_chunks:
                if p["id"] == clean_id:
                    snippet = p["text"]
                    pages = p.get("pages", [])
                    start_times = p.get("start_times", [])
                    break

        timestamp_url = None
        if start_times and source_id and source_id_to_url:
            url = source_id_to_url.get(source_id)
            if url and ("youtube.com" in url or "youtu.be" in url):
                sec = int(start_times[0])
                if "?" in url:
                    timestamp_url = f"{url}&t={sec}s"
                else:
                    timestamp_url = f"{url}?t={sec}s"

        citations_meta.append({
            "index": i,
            "raw_id": clean_id,
            "source_id": source_id,
            "source_name": source_name,
            "snippet": snippet,
            "pages": pages,
            "start_times": start_times,
            "timestamp_url": timestamp_url
        })
        
        # Replace all instances of the full tag with the footnote or empty string
        for full_tag, cid in full_to_clean.items():
            if cid == clean_id:
                answer_footnoted = answer_footnoted.replace(full_tag, f"[{i}]")
                answer_plain = answer_plain.replace(full_tag, "")
        
    # Clean up excessive spacing
    answer_footnoted = re.sub(r' +', ' ', answer_footnoted).strip()
    answer_plain = re.sub(r' +', ' ', answer_plain).strip()
    
    # Clean up spaces before punctuation (e.g. "word ." -> "word.")
    for char in ['.', ',', ';', '?', '!']:
        answer_footnoted = answer_footnoted.replace(f" {char}", char)
        answer_plain = answer_plain.replace(f" {char}", char)
        
    return answer_footnoted, citations_meta, answer_plain

PRONOUN_PATTERN = re.compile(r"\b(he|she|it|they|him|her|his|their|this|that|them|those|these|did he|did she|was he|was she|what is he|what is she|where did he|where did she|first|second|third|last|point|step|response|answer|explanation|concept|detail|elaborate|clarify|expand)\b", re.IGNORECASE)

async def _rewrite_query_if_needed(question: str, history: Optional[List[Dict[str, str]]], ollama_url: Optional[str], model_name: str) -> str:
    # If no history, or no pronouns found in the question, return the original question
    if not history or not PRONOUN_PATTERN.search(question):
        return question
        
    # Construct history string
    history_str = ""
    for turn in history[-3:]: # only last 3 turns to keep it super lightweight
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
            "num_predict": 30, # limit response length to avoid runaway generation
            "num_ctx": 1024
        }
    }
    
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code == 200:
                rewritten = response.json().get("response", "").strip()
                # Clean up any quotes
                rewritten = rewritten.strip('"\'')
                if rewritten:
                    logger.info(f"Rewrote query: '{question}' -> '{rewritten}'")
                    return rewritten
    except Exception as e:
        logger.error(f"Failed to rewrite query: {e}")
        
    return question

def _prepare_rag_prompt(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    similarity_threshold: Optional[float] = None,
    history: Optional[List[Dict[str, str]]] = None
) -> Tuple[str, str, List[Dict[str, Any]], List[Dict[str, Any]], List[str], Optional[str]]:
    refusal_msg = None
    workspace_dir = settings.workspaces_dir / workspace_id
    usearch_file = workspace_dir / "index.usearch"
    faiss_file = workspace_dir / "index.faiss"

    if not usearch_file.exists() and not faiss_file.exists():
        raise FileNotFoundError("Knowledge base index is not compiled. Please process your sources first.")

    # 1. Intent Routing
    is_global_summary = bool(GLOBAL_SUMMARY_REGEX.search(question))
    routing_mode = "GLOBAL_SUMMARY" if is_global_summary else "STANDARD_QA"
    k = 3  # Optimized Top-K
    
    is_meta_retrieval = False
    if not is_global_summary and INTENT_REGEX.search(question):
        routing_mode = "META_RETRIEVAL"
        k = 6
        is_meta_retrieval = True

    system_prompt = get_adaptive_system_prompts(model_name, is_strict, is_meta_retrieval=is_meta_retrieval)

    logger.info(f"Question routed to {routing_mode} (Top-K={k}), is_strict={is_strict}")

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
                logger.info(f"Parent chunk {p['id']} excluded. Adding it would exceed budget ({current_tokens + p_tokens} > {max_parent_tokens}).")
                continue
            current_tokens += p_tokens
            context_parts.append(f'<chunk id="{p["id"]}">\n{p_text}\n</chunk>')
            parent_ids_used.append(p["id"])
            retrieved_parent_chunks.append({
                "id": p["id"],
                "text": p_text,
                "score": 1.0
            })
    else:
        # Load or compile usearch index
        index = _get_or_build_usearch_index(workspace_id, workspace_dir)

        # 2. Vector Search (Child Chunks)
        model = get_embedding_model()
        query_emb = model.encode([question], normalize_embeddings=True)[0]
        query_contiguous = query_emb.copy().astype(np.float32)

        results = index.search(query_contiguous, k)
        scores = [[1.0 - d for d in results.distances]]
        indices = [results.keys]
        
        # Early check for strict mode: similarity score threshold
        threshold = similarity_threshold if similarity_threshold is not None else 0.25
        if is_strict:
            if len(scores) == 0 or len(scores[0]) == 0 or scores[0][0] < threshold:
                refusal_msg = "This topic is not present in the uploaded sources. Try turning off Strict Source Mode to search using general AI knowledge."
                return "", routing_mode, [], [], [], refusal_msg

        valid_indices = [int(idx) for idx in indices[0] if idx >= 0]

        # Load matching child chunks from SQLite
        from app.core.database import get_child_chunks_by_global_indices, get_parent_chunks_by_ids
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
                    "metadata": c_chunk.get("metadata", {})
                }
                retrieved_child_chunks.append(c_record)

                if parent_id is not None:
                    if parent_id not in parent_keys_seen:
                        parent_keys_seen.add(parent_id)
                        parent_records.append({
                            "score": float(score),
                            "parent_id": parent_id
                        })

        # Sort parent records in descending order of child chunk similarity score
        parent_records.sort(key=lambda x: x["score"], reverse=True)

        # 3. Load Parents and enforce budget (max 2000 tokens for context budgeting)
        parent_ids = [r["parent_id"] for r in parent_records if r["parent_id"] is not None]
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
                    logger.info(f"Parent chunk {p_id} ({p_tokens} tokens) excluded. Adding it would exceed budget ({current_tokens + p_tokens} > {max_parent_tokens}).")
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

                retrieved_parent_chunks.append({
                    "id": p_id,
                    "text": p_text,
                    "score": p_rec["score"],
                    "pages": sorted(list(set(pages))),
                    "start_times": sorted(list(set(start_times)))
                })

    context_str = "\n".join(context_parts)

    # Check for empty context in strict mode
    if is_strict:
        if len(retrieved_parent_chunks) == 0:
            refusal_msg = "This topic is not present in the uploaded sources. Try turning off Strict Source Mode to search using general AI knowledge."
            return "", routing_mode, retrieved_child_chunks, [], [], refusal_msg

    # 4. Load Custom Workspace Instructions
    instructions = ""
    metadata_file = workspace_dir / "metadata.json"
    if metadata_file.exists():
        try:
            with open(metadata_file, "r") as f:
                meta_data = json.load(f)
                instructions = meta_data.get("instructions", "").strip()
        except Exception as e:
            logger.error(f"Failed to read instructions from metadata for {workspace_id}: {e}")

    # Inject workspace instructions if present
    if instructions:
        system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n" + system_prompt
        instruction_block = f"\nCRITICAL CUSTOM INSTRUCTION (Apply this strictly to your answer): {instructions}\n"
        system_prompt = system_prompt.replace("Answer:", f"{instruction_block}\nAnswer:")

    prompt = system_prompt.format(context=context_str, question=question)
    if history:
        history_str = ""
        for turn in history[-4:]:
            role = "User" if turn.get("role") == "user" else "Assistant"
            content = turn.get("content", "").strip()
            history_str += f"{role}: {content}\n"
        if history_str:
            prompt = f"Previous Conversation History:\n{history_str}\n\n{prompt}"

    return prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg

async def retrieve_and_generate(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None
) -> Dict[str, Any]:
    """
    Executes RAG and generates answer asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)
    
    if not is_strict:
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
                logger.error(f"Failed to read instructions from metadata for {workspace_id}: {e}")

        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if instructions:
            system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n" + system_prompt
            
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
                "num_ctx": settings.ollama_num_ctx
            }
        }
        
        raw_answer = ""
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    result = response.json()
                    raw_answer = result.get("response", "").strip()
                else:
                    raw_answer = f"Error: Ollama returned status code {response.status_code}"
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
            "routing_mode": "CREATIVE_CHAT",
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": []
        }

    try:
        prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg = _prepare_rag_prompt(
            workspace_id, question, model_name=model_name, max_parent_tokens=max_parent_tokens, is_strict=is_strict,
            similarity_threshold=similarity_threshold, history=history
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
            "latency_ms": int((time.time() - t_start) * 1000)
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
            "latency_ms": int((time.time() - t_start) * 1000)
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
            "recommended_questions": []
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
            "num_ctx": settings.ollama_num_ctx
        }
    }

    raw_answer = ""
    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code == 200:
                result = response.json()
                raw_answer = result.get("response", "").strip()
            else:
                raw_answer = f"Error: Ollama returned status code {response.status_code}"
    except Exception as e:
        raw_answer = f"Error calling Ollama API: {e}"

    # Load sources to get source names for citation metadata
    from app.api.routes.sources import load_sources
    try:
        sources = load_sources(workspace_id)
        source_id_to_name = {s.id: s.name for s in sources}
        source_id_to_url = {s.id: s.url for s in sources if s.url}
    except Exception:
        source_id_to_name = {}
        source_id_to_url = {}

    # 5. Claim Sanitization
    answer_footnoted, citations_meta, answer_plain = sanitize_response(raw_answer, source_id_to_name, retrieved_parent_chunks, source_id_to_url)
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
        "recommended_questions": []
    }

async def retrieve_and_generate_stream(
    workspace_id: str,
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None
):
    """
    Executes RAG and yields Server-Sent Events (SSE) token chunks asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)
    
    if not is_strict:
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
                logger.error(f"Failed to read instructions from metadata for {workspace_id}: {e}")

        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if instructions:
            system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n- {instructions}\n\n" + system_prompt
            
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
                "num_ctx": settings.ollama_num_ctx
            }
        }

        full_text_buffer = ""
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
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
        except Exception as e:
            yield f"data: {json.dumps({'token': f'Error streaming from Ollama: {e}', 'done': True, 'error': True})}\n\n"
            return

        latency_ms = int((time.time() - t_start) * 1000)
        yield f"data: {json.dumps({'done': True, 'answer': full_text_buffer.strip(), 'plain_answer': full_text_buffer.strip(), 'citations': [], 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"
        return

    try:
        prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg = _prepare_rag_prompt(
            workspace_id, question, model_name=model_name, max_parent_tokens=max_parent_tokens, is_strict=is_strict,
            similarity_threshold=similarity_threshold, history=history
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

    base_url = ollama_url if ollama_url else settings.ollama_base_url
    url = f"{base_url}/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "stream": True,
        "options": {
            "temperature": temperature if temperature is not None else 0.0,
            "num_thread": max(1, multiprocessing.cpu_count() // 2),
            "num_ctx": settings.ollama_num_ctx
        }
    }

    full_text_buffer = ""
    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
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
    except Exception as e:
        yield f"data: {json.dumps({'token': f'Error streaming from Ollama: {e}', 'done': True, 'error': True})}\n\n"
        return

    # Load source names for citation mapping
    from app.api.routes.sources import load_sources
    try:
        sources = load_sources(workspace_id)
        source_id_to_name = {s.id: s.name for s in sources}
        source_id_to_url = {s.id: s.url for s in sources if s.url}
    except Exception:
        source_id_to_name = {}
        source_id_to_url = {}

    answer_footnoted, citations_meta, answer_plain = sanitize_response(full_text_buffer.strip(), source_id_to_name, retrieved_parent_chunks, source_id_to_url)
    latency_ms = int((time.time() - t_start) * 1000)

    # Yield the final control message with all citations and followups
    yield f"data: {json.dumps({'done': True, 'answer': answer_footnoted, 'plain_answer': answer_plain, 'citations': citations_meta, 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"


def _prepare_universal_rag_prompt(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    similarity_threshold: Optional[float] = None,
    history: Optional[List[Dict[str, str]]] = None
) -> Tuple[str, str, List[Dict[str, Any]], List[Dict[str, Any]], List[str], Optional[str], Dict[str, str]]:
    refusal_msg = None
    is_global_summary = bool(GLOBAL_SUMMARY_REGEX.search(question))
    routing_mode = "GLOBAL_SUMMARY" if is_global_summary else "STANDARD_QA"
    k = 4  # Top-K child chunks per workspace to fetch
    
    is_meta_retrieval = False
    if not is_global_summary and INTENT_REGEX.search(question):
        routing_mode = "META_RETRIEVAL"
        k = 8
        is_meta_retrieval = True

    system_prompt = get_adaptive_system_prompts(model_name, is_strict, is_meta_retrieval=is_meta_retrieval)

    logger.info(f"Universal Question routed to {routing_mode} (per-workspace Top-K={k}), is_strict={is_strict}")

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
                        workspace_instructions.append(f"Workspace '{ws_name}' Instructions: {inst}")
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
                logger.error(f"Error loading sequential parent chunks for universal workspace {ws_id}: {e}")
                db_parents = []
            
            for p in db_parents:
                p_text = p["text"]
                p_tokens = estimate_tokens(p_text)
                if current_tokens + p_tokens > max_parent_tokens:
                    logger.info(f"Universal parent chunk {p['id']} excluded due to budget.")
                    continue
                current_tokens += p_tokens
                context_parts.append(f'<chunk id="{p["id"]}" workspace="{ws_name}">\n{p_text}\n</chunk>')
                parent_ids_used.append(p["id"])
                retrieved_parent_chunks.append({
                    "id": p["id"],
                    "text": p_text,
                    "score": 1.0,
                    "workspace_id": ws_id,
                    "workspace_name": ws_name
                })
    else:
        # Generate query embedding
        model = get_embedding_model()
        query_emb = model.encode([question], normalize_embeddings=True)[0]
        query_contiguous = query_emb.copy().astype(np.float32)
        # Loop over all requested workspace IDs for vector search
        for ws_id in workspace_ids:
            workspace_dir = settings.workspaces_dir / ws_id

            try:
                index = _get_or_build_usearch_index(ws_id, workspace_dir)
                results = index.search(query_contiguous, k)
                scores = [[1.0 - d for d in results.distances]]
                indices = [results.keys]
                valid_indices = [int(idx) for idx in indices[0] if idx >= 0]
                
                if not valid_indices:
                    continue

                from app.core.database import get_child_chunks_by_global_indices
                db_chunks = get_child_chunks_by_global_indices(ws_id, valid_indices)
                chunks_by_global_idx = {c["global_vector_index"]: c for c in db_chunks}

                for rank, (score, chunk_idx) in enumerate(zip(scores[0], indices[0]), 1):
                    chunk_idx_int = int(chunk_idx)
                    if chunk_idx_int in chunks_by_global_idx:
                        c_chunk = chunks_by_global_idx[chunk_idx_int]
                        all_child_chunks.append({
                            "workspace_id": ws_id,
                            "workspace_name": workspace_names.get(ws_id, ws_id),
                            "rank_local": rank,
                            "score": float(score),
                            "id": c_chunk["id"],
                            "text": c_chunk["text"],
                            "parent_id": c_chunk["parent_id"],
                            "metadata": c_chunk.get("metadata", {})
                        })
                
                from app.api.routes.sources import load_sources
                try:
                    sources = load_sources(ws_id)
                    for s in sources:
                        source_id_to_name[s.id] = f"{workspace_names.get(ws_id, ws_id)} > {s.name}"
                        if s.url:
                            source_id_to_url[s.id] = s.url
                except Exception:
                    pass

            except Exception as e:
                logger.error(f"Error performing vector search in workspace {ws_id}: {e}")

        all_child_chunks.sort(key=lambda x: x["score"], reverse=True)

        threshold = similarity_threshold if similarity_threshold is not None else 0.25
        if is_strict:
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
                    parent_records.append({
                        "score": c["score"],
                        "parent_id": parent_id,
                        "workspace_id": ws_id,
                        "workspace_name": c["workspace_name"]
                    })

        parent_records.sort(key=lambda x: x["score"], reverse=True)

        from app.core.database import get_parent_chunks_by_ids
        parents_by_workspace_and_id = {}

        for ws_id in workspace_ids:
            ws_parent_ids = [r["parent_id"] for r in parent_records if r["workspace_id"] == ws_id]
            if ws_parent_ids:
                try:
                    db_parents = get_parent_chunks_by_ids(ws_id, ws_parent_ids)
                    parents_by_workspace_and_id[ws_id] = {p["id"]: p["text"] for p in db_parents}
                except Exception as e:
                    logger.error(f"Failed to load parent chunks for workspace {ws_id}: {e}")

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
                    logger.info(f"Parent chunk {p_id} from {ws_name} excluded due to budget.")
                    continue

                current_tokens += p_tokens
                context_parts.append(f'<chunk id="{p_id}" workspace="{ws_name}">\n{p_text}\n</chunk>')
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

                retrieved_parent_chunks.append({
                    "id": p_id,
                    "text": p_text,
                    "score": p_rec["score"],
                    "workspace_id": ws_id,
                    "workspace_name": ws_name,
                    "pages": sorted(list(set(pages))),
                    "start_times": sorted(list(set(start_times)))
                })

    context_str = "\n".join(context_parts)

    if is_strict:
        if len(retrieved_parent_chunks) == 0:
            refusal_msg = "This topic is not present in the uploaded sources. Try turning off Strict Source Mode to search using general AI knowledge."
            return "", routing_mode, all_child_chunks, [], [], refusal_msg, source_id_to_name, source_id_to_url

    instructions = "\n".join(workspace_instructions).strip()
    if instructions:
        system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions}\n\n" + system_prompt
        instruction_block = f"\nCRITICAL CUSTOM INSTRUCTION (Apply this strictly to your answer): {instructions}\n"
        system_prompt = system_prompt.replace("Answer:", f"{instruction_block}\nAnswer:")

    prompt = system_prompt.format(context=context_str, question=question)
    if history:
        history_str = ""
        for turn in history[-4:]:
            role = "User" if turn.get("role") == "user" else "Assistant"
            content = turn.get("content", "").strip()
            history_str += f"{role}: {content}\n"
        if history_str:
            prompt = f"Previous Conversation History:\n{history_str}\n\n{prompt}"

    return prompt, routing_mode, all_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg, source_id_to_name, source_id_to_url


async def retrieve_and_generate_universal(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None
) -> Dict[str, Any]:
    """
    Executes RAG across multiple workspaces and generates answer asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)
    
    if not is_strict:
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
                            workspace_instructions.append(f"Workspace '{ws_name}' Instructions: {inst}")
                except Exception as e:
                    logger.error(f"Failed to read metadata for workspace {ws_id}: {e}")
        
        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if workspace_instructions:
            instructions_str = "\n".join(workspace_instructions).strip()
            system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions_str}\n\n" + system_prompt
            
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
                "num_ctx": settings.ollama_num_ctx
            }
        }

        raw_answer = ""
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    result = response.json()
                    raw_answer = result.get("response", "").strip()
                else:
                    raw_answer = f"Error: Ollama returned status code {response.status_code}"
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
            "routing_mode": "CREATIVE_CHAT",
            "latency_ms": int((time.time() - t_start) * 1000),
            "recommended_questions": []
        }

    try:
        prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg, source_id_to_name, source_id_to_url = _prepare_universal_rag_prompt(
            workspace_ids, question, model_name=model_name, max_parent_tokens=max_parent_tokens, is_strict=is_strict,
            similarity_threshold=similarity_threshold, history=history
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
            "latency_ms": int((time.time() - t_start) * 1000)
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
            "recommended_questions": []
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
            "num_ctx": settings.ollama_num_ctx
        }
    }

    raw_answer = ""
    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code == 200:
                result = response.json()
                raw_answer = result.get("response", "").strip()
            else:
                raw_answer = f"Error: Ollama returned status code {response.status_code}"
    except Exception as e:
        raw_answer = f"Error calling Ollama API: {e}"

    # Claim Sanitization
    answer_footnoted, citations_meta, answer_plain = sanitize_response(raw_answer, source_id_to_name, retrieved_parent_chunks, source_id_to_url)
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
        "recommended_questions": []
    }

async def retrieve_and_generate_universal_stream(
    workspace_ids: List[str],
    question: str,
    model_name: str = "qwen2.5:1.5b",
    max_parent_tokens: int = 2000,
    is_strict: bool = True,
    temperature: Optional[float] = None,
    similarity_threshold: Optional[float] = None,
    ollama_url: Optional[str] = None,
    history: Optional[List[Dict[str, str]]] = None
):
    """
    Executes universal RAG and yields Server-Sent Events (SSE) token chunks asynchronously.
    """
    t_start = time.time()
    original_question = question
    question = await _rewrite_query_if_needed(question, history, ollama_url, model_name)
    
    if not is_strict:
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
                            workspace_instructions.append(f"Workspace '{ws_name}' Instructions: {inst}")
                except Exception as e:
                    logger.error(f"Failed to read metadata for workspace {ws_id}: {e}")
        
        system_prompt = "You are a helpful AI assistant. Answer the user's question using your pre-trained general knowledge. Do not mention or cite any document chunks or source files. Write your response in clean Markdown."
        if workspace_instructions:
            instructions_str = "\n".join(workspace_instructions).strip()
            system_prompt = f"CRITICAL WORKSPACE SYSTEM INSTRUCTIONS:\n{instructions_str}\n\n" + system_prompt
            
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
                "num_ctx": settings.ollama_num_ctx
            }
        }

        full_text_buffer = ""
        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
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
        except Exception as e:
            yield f"data: {json.dumps({'token': f'Error streaming from Ollama: {e}', 'done': True, 'error': True})}\n\n"
            return

        latency_ms = int((time.time() - t_start) * 1000)
        yield f"data: {json.dumps({'done': True, 'answer': full_text_buffer.strip(), 'plain_answer': full_text_buffer.strip(), 'citations': [], 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"
        return

    try:
        prompt, routing_mode, retrieved_child_chunks, retrieved_parent_chunks, parent_ids_used, refusal_msg, source_id_to_name, source_id_to_url = _prepare_universal_rag_prompt(
            workspace_ids, question, model_name=model_name, max_parent_tokens=max_parent_tokens, is_strict=is_strict,
            similarity_threshold=similarity_threshold, history=history
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
            "num_ctx": settings.ollama_num_ctx
        }
    }

    full_text_buffer = ""
    try:
        async with httpx.AsyncClient(timeout=180.0) as client:
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
    except Exception as e:
        yield f"data: {json.dumps({'token': f'Error streaming from Ollama: {e}', 'done': True, 'error': True})}\n\n"
        return

    answer_footnoted, citations_meta, answer_plain = sanitize_response(full_text_buffer.strip(), source_id_to_name, retrieved_parent_chunks, source_id_to_url)
    latency_ms = int((time.time() - t_start) * 1000)

    yield f"data: {json.dumps({'done': True, 'answer': answer_footnoted, 'plain_answer': answer_plain, 'citations': citations_meta, 'recommended_questions': [], 'latency_ms': latency_ms})}\n\n"


