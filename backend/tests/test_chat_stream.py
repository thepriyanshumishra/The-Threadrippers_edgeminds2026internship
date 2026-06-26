import sys
import json
import asyncio
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add backend directory to sys.path
backend_path = Path(__file__).resolve().parents[1]
sys.path.append(str(backend_path))

from app.core.retriever import retrieve_and_generate_stream

class MockAsyncIterator:
    def __init__(self, items):
        self.items = items
    def __aiter__(self):
        return self
    async def __anext__(self):
        if not self.items:
            raise StopAsyncIteration
        return self.items.pop(0)

class MockStreamContext:
    def __init__(self, response):
        self.response = response
    async def __aenter__(self):
        return self.response
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass

def test_retrieve_and_generate_stream_success():
    # Mock prompt preparation helper
    mock_prompt = "Mock system prompt context question"
    mock_routing = "STANDARD_QA"
    mock_children = [{"id": "c1", "text": "child text"}]
    mock_parents = [{"id": "p1", "text": "parent text"}]
    mock_parent_ids = ["p1"]

    # Mock Ollama stream response
    mock_lines = [
        '{"response": "Here", "done": false}',
        '{"response": " is", "done": false}',
        '{"response": " the", "done": false}',
        '{"response": " answer", "done": false}',
        '{"response": " [doc1_p0].", "done": true}'
    ]

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.aiter_lines.return_value = MockAsyncIterator(mock_lines)

    # Mock load_sources to return dynamic source name
    mock_source = MagicMock()
    mock_source.id = "doc1"
    mock_source.name = "Test Doc.pdf"

    with patch("app.core.retriever._prepare_rag_prompt") as mock_prep:
        mock_prep.return_value = (mock_prompt, mock_routing, mock_children, mock_parents, mock_parent_ids, None)
        
        with patch("httpx.AsyncClient") as mock_client_class:
            mock_client_instance = MagicMock()
            mock_client_class.return_value.__aenter__.return_value = mock_client_instance
            mock_client_instance.stream.return_value = MockStreamContext(mock_response)
            
            with patch("app.api.routes.sources.load_sources", return_value=[mock_source]):
                
                # Run the async generator
                async def run_test():
                    generator = retrieve_and_generate_stream(
                        workspace_id="test_ws",
                        question="test query"
                    )
                    events = []
                    async for e in generator:
                        events.append(e)
                    return events
                
                events = asyncio.run(run_test())
                
                # Check output events
                assert len(events) > 0
                
                # Verify that tokens are streamed
                token_events = [json.loads(e.replace("data: ", "").strip()) for e in events if not json.loads(e.replace("data: ", "").strip()).get("done")]
                assert len(token_events) > 0
                assert "".join([t["token"] for t in token_events]) == "Here is the answer [doc1_p0]."
                
                # Verify that the <followup> tag and its content are NOT in the token stream
                for t in token_events:
                    assert "<followup>" not in t["token"]
                    assert "Follow up" not in t["token"]
                
                # Verify the final control chunk
                final_event = json.loads(events[-1].replace("data: ", "").strip())
                assert final_event["done"] is True
                assert "[1]" in final_event["answer"]
                assert final_event["citations"][0]["source_name"] == "Test Doc.pdf"
                assert len(final_event["recommended_questions"]) == 0
