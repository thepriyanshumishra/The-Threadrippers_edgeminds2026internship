# Contributing to Kivo Workspace

Thank you for your interest in contributing! This guide covers everything you need to get the full development environment running from source code.

> **End users** looking to just run the app should use the installers in [README.md](README.md) instead.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting the Source Code](#getting-the-source-code)
- [Backend Setup (FastAPI)](#backend-setup-fastapi)
- [Frontend Setup (Flutter)](#frontend-setup-flutter)
- [Running the Full Stack](#running-the-full-stack)
- [One-Command Developer Launch](#one-command-developer-launch)
- [Running Tests](#running-tests)
- [Project Architecture](#project-architecture)
- [Code Style & Conventions](#code-style--conventions)
- [Submitting a Pull Request](#submitting-a-pull-request)

---

## Prerequisites

Install all of the following before starting:

### 1. Ollama (Local LLM runtime)
Download and install from [ollama.com](https://ollama.com), then pull the default model:
```bash
ollama pull qwen2.5:1.5b
```
Make sure Ollama is running in the background before launching the backend.

### 2. Python 3.11 or 3.12
- **macOS:** `brew install python@3.12`
- **Linux:** `sudo apt-get install python3.12 python3.12-venv`
- **Windows:** Download from [python.org](https://www.python.org/downloads/) — check "Add to PATH"

### 3. Flutter SDK 3.22+
Follow the official install guide: [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install)

Verify with:
```bash
flutter doctor
```
Fix any issues reported by `flutter doctor` before proceeding (especially desktop platform enablement).

Enable macOS/Windows/Linux desktop targets:
```bash
flutter config --enable-macos-desktop   # macOS
flutter config --enable-windows-desktop # Windows
flutter config --enable-linux-desktop   # Linux
```

### 4. FFmpeg (Audio/Video extraction)
- **macOS:** `brew install ffmpeg`
- **Linux:** `sudo apt-get install -y ffmpeg`
- **Windows:** Download from [ffmpeg.org](https://ffmpeg.org/download.html) and add to PATH

### 5. Tesseract OCR (Image text extraction)
- **macOS:** `brew install tesseract`
- **Linux:** `sudo apt-get install -y tesseract-ocr`
- **Windows:** Install from [UB-Mannheim builds](https://github.com/UB-Mannheim/tesseract/wiki) and add to PATH

### 6. Git
```bash
# macOS
brew install git

# Linux
sudo apt-get install -y git
```

---

## Getting the Source Code

```bash
git clone https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship.git
cd The-Threadrippers_edgeminds2026internship
```

---

## Backend Setup (FastAPI)

The backend is a Python FastAPI application. All dependencies are managed inside a virtual environment.

```bash
cd backend

# Create the virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate          # macOS/Linux
# venv\Scripts\activate           # Windows (Command Prompt)
# venv\Scripts\Activate.ps1       # Windows (PowerShell)

# Install production dependencies
pip install --upgrade pip
pip install -r requirements.txt

# Install development dependencies (pytest, etc.)
pip install -r requirements-dev.txt

# Install Playwright's Chromium browser (required for website extraction)
playwright install chromium

# Start the backend server
python -m uvicorn main:app --port 8000
```

The API will be available at `http://localhost:8000`.  
Interactive API docs (Swagger UI): `http://localhost:8000/docs`

**Verify it's working:**
```bash
curl http://localhost:8000/system/diagnostics
```

### Backend Environment Variables (optional)

The backend reads from `app/core/config.py` using Pydantic Settings. You can override any setting with environment variables or a `.env` file in the `backend/` directory:

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_DEFAULT_MODEL` | `qwen2.5:1.5b` | Default LLM model name |
| `DEBUG` | `false` | Enable debug logging |

Example `backend/.env`:
```env
OLLAMA_DEFAULT_MODEL=qwen2.5:7b
```

> `.env` files are gitignored — never commit them.

---

## Frontend Setup (Flutter)

The frontend is a Flutter desktop application.

```bash
cd frontend

# Fetch Dart/Flutter packages
flutter pub get

# Run on your platform
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
```

Flutter will connect to the backend at `http://localhost:8000` automatically (configured in `lib/core/config/app_config.dart`).

### Useful Flutter commands

```bash
# Check for analysis issues
flutter analyze

# Run with verbose logging
flutter run -d macos -v

# Build a release binary (don't use for dev)
flutter build macos --release
```

---

## Running the Full Stack

You need **two terminals** running simultaneously (or use the one-command launcher below):

**Terminal 1 — Backend:**
```bash
cd backend
source venv/bin/activate
python -m uvicorn main:app --port 8000
```

**Terminal 2 — Frontend:**
```bash
cd frontend
flutter run -d macos   # or windows / linux
```

---

## One-Command Developer Launch

The setup scripts handle the full flow automatically — they create the venv, install dependencies, and launch both the backend and frontend concurrently:

```bash
# macOS / Linux
./setup.sh

# Windows (PowerShell — run as Administrator if needed)
.\setup.ps1
```

> **Note:** These scripts install everything and then launch the app. On first run they take a few minutes (model download, pip install). Subsequent runs are fast.

The backend is started as a background process. When you close the Flutter window or press `Ctrl+C`, the backend is automatically killed too.

---

## Running Tests

The backend has a pytest test suite covering the retrieval engine, chunking pipeline, and YouTube processor.

```bash
cd backend
source venv/bin/activate

# Run all tests
pytest tests/ -v

# Run a specific test file
pytest tests/test_retriever.py -v

# Run with output capture disabled (see print statements)
pytest tests/ -v -s
```

**Current test coverage:**
- `test_retriever.py` — sanitize_response, token estimation, citation mapping
- `test_chat_stream.py` — full RAG stream pipeline (mocked Ollama)
- `test_chunking.py` — chunk boundary detection, parent-child hierarchy
- `test_youtube.py` — YouTube subtitle fetch and audio fallback

---

## Project Architecture

### Backend (`backend/`)

| File / Folder | Purpose |
|---|---|
| `main.py` | FastAPI app, CORS config, middleware, router registration |
| `app/core/config.py` | Pydantic settings — reads from env vars / `.env` |
| `app/core/retriever.py` | RAG engine: FAISS search, prompt construction, Ollama streaming |
| `app/core/database.py` | SQLite helpers: parent/child chunk storage and retrieval |
| `app/core/processors/` | Extraction pipelines: PDF, OCR, audio, YouTube, web, embeddings |
| `app/api/routes/workspaces.py` | Workspace CRUD endpoints |
| `app/api/routes/sources.py` | Source upload, registration, and listing |
| `app/api/routes/processing.py` | Background processing queue and status |
| `app/api/routes/chat.py` | Workspace-scoped chat (streaming + non-streaming) |
| `app/api/routes/universal_chat.py` | Cross-workspace multi-source chat |

### Frontend (`frontend/lib/`)

| Folder | Purpose |
|---|---|
| `features/workspace/` | Workspace list, creation, and detail screens |
| `features/sources/` | Source upload grid and processing status |
| `features/chat/` | Chat UI, message bubbles, citation panel, streaming |
| `features/settings/` | Model selection, Ollama URL config |
| `core/theme/` | Color tokens, typography, dark/light mode |
| `core/network/` | API client (Dio-based) and SSE stream handler |

### Data Flow

```
User uploads a PDF
    → Backend extracts text (PyMuPDF)
    → Chunks into parent/child hierarchy (SQLite)
    → Embeds child chunks (ONNX GTE multilingual model)
    → Stores vectors in FAISS index file

User sends a chat message (Strict Mode)
    → Backend embeds the query
    → FAISS similarity search → top-K child chunks
    → Loads parent chunks for full context
    → Constructs prompt with context
    → Streams Ollama response token-by-token via SSE
    → sanitize_response() maps raw chunk IDs to numbered citations [1][2]
    → Frontend renders markdown + citation chips
```

---

## Code Style & Conventions

### Python (Backend)
- Follow **PEP 8**
- Use **type hints** on all function signatures
- Log using the module-level `logger = logging.getLogger("kivo.module_name")` pattern
- Never expose raw exception messages in HTTP responses — log them, return generic user-facing strings
- Keep route handlers thin — business logic belongs in `core/`

### Dart/Flutter (Frontend)
- Follow standard Dart/Flutter style (`flutter analyze` must pass with zero issues)
- Use **Riverpod** for all state management — no `setState` in feature screens
- Keep widgets small and focused — extract to separate files when a widget exceeds ~100 lines
- Use the `AppColors` / `AppTheme` token system — never hardcode hex colors inline

### Git Commits
Use conventional commit format:
```
feat: add website source extraction
fix: handle empty FAISS index gracefully
refactor: extract citation mapping to sanitize_response
docs: update CONTRIBUTING with env var table
```

---

## Submitting a Pull Request

1. **Open an issue first** for anything significant — let's align before you invest time coding
2. Fork the repository and create a branch:
   ```bash
   git checkout -b feat/my-feature
   ```
3. Make your changes
4. Run the backend tests and ensure they pass:
   ```bash
   cd backend && ./venv/bin/pytest tests/ -v
   ```
5. Run Flutter analyze and fix any issues:
   ```bash
   cd frontend && flutter analyze
   ```
6. Push and open a Pull Request against `main`
7. Fill in the PR template — describe what changed and why

**PR checklist:**
- [ ] Backend tests pass (`pytest`)
- [ ] Flutter analysis clean (`flutter analyze`)  
- [ ] No hardcoded secrets or absolute paths
- [ ] New features have at least one test
- [ ] README / docs updated if user-facing behavior changed

---

## Common Issues

### `playwright install` fails on Linux
```bash
playwright install chromium --with-deps
```

### `faiss` import causes OpenMP crash on macOS
This is fixed in the codebase — `import torch` must appear before `import faiss` in `retriever.py`. Do not reorder these imports.

### Flutter can't find the backend
Make sure the backend is running (`curl http://localhost:8000/system/diagnostics` should return JSON), and that no firewall is blocking `localhost:8000`.

### Ollama model not found
```bash
ollama list          # see what's installed
ollama pull qwen2.5:1.5b   # pull the default
```

---

*For questions or help, open a [GitHub Issue](https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/issues).*
