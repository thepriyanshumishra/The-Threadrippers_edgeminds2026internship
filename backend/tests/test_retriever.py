import sys
from pathlib import Path

# Add backend directory to sys.path
backend_path = Path(__file__).resolve().parents[1]
sys.path.append(str(backend_path))

from app.core.retriever import sanitize_response, estimate_tokens, get_adaptive_system_prompts

def test_estimate_tokens():
    assert estimate_tokens("hello world") == int(2 * 1.3)
    assert estimate_tokens("") == 0

def test_sanitize_response_empty():
    answer_footnoted, citations_meta, answer_plain = sanitize_response("")
    assert answer_footnoted == ""
    assert citations_meta == []
    assert answer_plain == ""

def test_sanitize_response_no_citations():
    text = "This is a clean response with no citations."
    answer_footnoted, citations_meta, answer_plain = sanitize_response(text)
    assert answer_footnoted == text
    assert citations_meta == []
    assert answer_plain == text

def test_sanitize_response_with_chunk_tags():
    text = "This is <chunk id=\"1\">important</chunk> info."
    answer_footnoted, citations_meta, answer_plain = sanitize_response(text)
    assert answer_footnoted == "This is important info."
    assert citations_meta == []
    assert answer_plain == "This is important info."

def test_sanitize_response_with_citations():
    text = "Here is some fact [source_123_p0]. And another one [source_123_c1]."
    source_map = {"source_123": "My Document.pdf"}
    
    answer_footnoted, citations_meta, answer_plain = sanitize_response(text, source_map)
    
    # Check footnoted text has replaced citation tags with sequential indices
    assert "[1]" in answer_footnoted
    assert "[2]" in answer_footnoted
    assert "[source_123_p0]" not in answer_footnoted
    
    # Check plain text has stripped citation tags completely
    assert "[1]" not in answer_plain
    assert "[source_123_p0]" not in answer_plain
    
    # Check metadata structure
    assert len(citations_meta) == 2
    assert citations_meta[0]["index"] == 1
    assert citations_meta[0]["raw_id"] == "source_123_p0"
    assert citations_meta[0]["source_id"] == "source_123"
    assert citations_meta[0]["source_name"] == "My Document.pdf"

def test_get_adaptive_system_prompts():
    # 1. Reasoning model
    reasoning_prompt = get_adaptive_system_prompts("deepseek-r1:1.5b", is_strict=True, is_meta_retrieval=False)
    assert "You are a grounded QA assistant" in reasoning_prompt
    assert "Format your response using professional Markdown" not in reasoning_prompt  # No complex guidelines
    
    # 2. Small model (not default Qwen)
    small_prompt = get_adaptive_system_prompts("gemma2:2b", is_strict=True, is_meta_retrieval=False)
    assert "Explain the answer simply and directly" in small_prompt
    assert "Use tables when presenting" not in small_prompt
    
    # 3. Default Qwen (uses full capable prompt)
    qwen_prompt = get_adaptive_system_prompts("qwen2.5:1.5b", is_strict=True, is_meta_retrieval=False)
    assert "Format your response using professional Markdown" in qwen_prompt
    assert "Use tables when presenting" in qwen_prompt
    
    # 4. Large model (uses full capable prompt)
    large_prompt = get_adaptive_system_prompts("llama3:70b", is_strict=True, is_meta_retrieval=False)
    assert "Format your response using professional Markdown" in large_prompt

def test_sanitize_response_with_enriched_metadata():
    text = "Tagore was born here [source_123_p0]. Watch doc [source_456_c1]."
    source_map = {"source_123": "My Document.pdf", "source_456": "Tagore video"}
    source_urls = {"source_456": "https://youtube.com/watch?v=dQw4w9WgXcQ"}
    parent_chunks = [
        {"id": "source_123_p0", "text": "Tagore birth info", "pages": [32, 38]},
        {"id": "source_456_c1", "text": "Tagore video segment", "start_times": [1928.0]}
    ]
    
    answer_footnoted, citations_meta, answer_plain = sanitize_response(
        text, source_map, parent_chunks, source_urls
    )
    
    assert "[1]" in answer_footnoted
    assert "[2]" in answer_footnoted
    
    assert len(citations_meta) == 2
    assert citations_meta[0]["pages"] == [32, 38]
    assert citations_meta[0]["snippet"] == "Tagore birth info"
    
    assert citations_meta[1]["start_times"] == [1928.0]
    assert "t=1928s" in citations_meta[1]["timestamp_url"]

