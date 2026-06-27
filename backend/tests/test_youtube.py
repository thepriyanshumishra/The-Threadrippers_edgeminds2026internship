import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add backend directory to sys.path
backend_path = Path(__file__).resolve().parents[1]
sys.path.append(str(backend_path))

from app.core.processors.youtube import YouTubeProcessor

def test_youtube_processor_subtitle_success():
    mock_audio_processor = MagicMock()
    mock_audio_processor.create_chunks_from_segments.return_value = {
        "stats": {"duration": 100.0, "words": 150, "chunks": 2},
        "summary": "Mock summary"
    }

    processor = YouTubeProcessor(mock_audio_processor)

    mock_info = {
        "title": "Mock Video Title",
        "duration": 100.0,
        "subtitles": {},
        "automatic_captions": {
            "en": [{"ext": "vtt", "url": "http://example.com/en.vtt"}],
            "hi": [{"ext": "vtt", "url": "http://example.com/hi.vtt"}]
        }
    }

    class MockYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            pass

        def extract_info(self, url, download=False):
            return mock_info

        def download(self, urls):
            pass

    with patch("yt_dlp.YoutubeDL", MockYoutubeDL):
        with patch("glob.glob") as mock_glob:
            mock_glob.return_value = ["/tmp/test_source_sub_temp.en.vtt"]
            
            fake_vtt = (
                "WEBVTT\n\n"
                "00:00:01.000 --> 00:00:05.000\n"
                "Hello world\n"
            )
            
            mock_open_file = MagicMock()
            mock_open_file.__enter__.return_value.read.return_value = fake_vtt
            
            with patch("builtins.open", return_value=mock_open_file):
                with patch("pathlib.Path.unlink") as mock_unlink:
                    res = processor.process(
                        url="https://youtube.com/watch?v=123",
                        workspace_id="test_ws",
                        source_id="test_source",
                        sources_dir=Path("/tmp")
                    )
                    
                    assert res["title"] == "Mock Video Title"
                    assert res["stats"]["chunks"] == 2
                    assert mock_audio_processor.create_chunks_from_segments.called
                    assert mock_unlink.called

def test_youtube_processor_fallback_to_audio():
    mock_audio_processor = MagicMock()
    mock_audio_processor.process.return_value = {
        "stats": {"duration": 200.0, "words": 300, "chunks": 5},
        "summary": "Audio fallback summary"
    }

    processor = YouTubeProcessor(mock_audio_processor)

    # Mock info dict returning no subtitles
    mock_info = {
        "title": "Mock Video No Subtitles",
        "duration": 200.0,
        "subtitles": {},
        "automatic_captions": {}
    }

    class MockYoutubeDL:
        def __init__(self, opts):
            self.opts = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            pass

        def extract_info(self, url, download=False):
            # If skip_download is False (Phase 2), we simulate download
            return mock_info

        def download(self, urls):
            pass

    with patch("yt_dlp.YoutubeDL", MockYoutubeDL):
        with patch("glob.glob", return_value=["/tmp/test_source_temp.mp3"]):
            # We mock path check for downloaded audio file to return True
            with patch("pathlib.Path.exists", return_value=True):
                with patch("pathlib.Path.unlink") as mock_unlink:
                    res = processor.process(
                        url="https://youtube.com/watch?v=456",
                        workspace_id="test_ws",
                        source_id="test_source",
                        sources_dir=Path("/tmp")
                    )
                
                assert res["title"] == "Mock Video No Subtitles"
                assert res["stats"]["chunks"] == 5
                assert mock_audio_processor.process.called
                assert mock_unlink.called
