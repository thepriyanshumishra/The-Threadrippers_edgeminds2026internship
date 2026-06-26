import sys
from pathlib import Path

# Add backend directory to sys.path
backend_path = Path(__file__).resolve().parents[1]
sys.path.append(str(backend_path))

from app.core.processors.text import find_chunk_boundaries, find_parent_child_boundaries

def test_find_chunk_boundaries_empty():
    assert find_chunk_boundaries("") == []

def test_find_chunk_boundaries_small_text():
    text = "Short text."
    result = find_chunk_boundaries(text, chunk_size=100)
    assert len(result) == 1
    assert result[0] == (0, len(text))
    assert text[result[0][0]:result[0][1]] == text

def test_find_chunk_boundaries_normal_split():
    text = "This is sentence one. This is sentence two. This is sentence three."
    # Set chunk size to fit approx 1 sentence (20 chars)
    result = find_chunk_boundaries(text, chunk_size=25, chunk_overlap=5)
    assert len(result) > 0
    # Every chunk should have non-empty text slice
    for start, end in result:
        assert start < end
        assert len(text[start:end].strip()) > 0

def test_find_parent_child_boundaries():
    text = "Lorem ipsum dolor sit amet. Consectetur adipiscing elit. Integer nec odio."
    parent_texts, child_boundaries = find_parent_child_boundaries(
        text, parent_size=50, parent_overlap=10, child_size=30, child_overlap=5
    )
    assert isinstance(parent_texts, list)
    assert isinstance(child_boundaries, list)
    assert len(parent_texts) >= 1
    for c_start, c_end, p_idx in child_boundaries:
        assert c_start < c_end
        assert p_idx < len(parent_texts)
        assert len(text[c_start:c_end].strip()) > 0
