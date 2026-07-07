<div align="center">

# Kivo Workspace

**A fully local, privacy-first AI knowledge workspace.**  
Upload documents, videos, websites, and audio — then chat with your knowledge base using a grounded AI that cites every claim.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)]()
[![Backend](https://img.shields.io/badge/Backend-FastAPI%20%2B%20Python%203.12-green)]()
[![Frontend](https://img.shields.io/badge/Frontend-Flutter%203.32-blue)]()
[![LLM](https://img.shields.io/badge/LLM-Ollama%20(local)-orange)]()

</div>

---

## What is Kivo Workspace?

Kivo Workspace is a **desktop application** that turns your documents, videos, and web pages into a private, searchable knowledge base — no cloud, no subscriptions, no data leaving your machine.

You create isolated **Workspaces** (one per topic or project), add sources, let Kivo process and index them, and then have a conversation with an AI that answers strictly from your sources — with numbered citations linking back to the exact text it used.

> **Everything runs on your device.** The embedding model, the vector database, and the language model (via Ollama) are all local. Nothing is ever sent to an external server.

---

## Key Features

| Feature | Description |
|---------|-------------|
| 📁 **Isolated Workspaces** | Each workspace has its own documents, vector index, and custom AI instructions |
| 📄 **PDF & Documents** | Clean, page-by-page text extraction using PyMuPDF |
| 🖼️ **Images (OCR)** | Local OCR via Tesseract for screenshots and scanned documents |
| 🎙️ **Audio Files** | Offline transcription via Faster-Whisper (`.mp3`, `.wav`, `.m4a`, `.flac`, `.ogg`) |
| 📺 **YouTube Videos** | Subtitle-first fetch (instant), fallback to local transcription if no subtitles exist |
| 🌐 **Websites** | Full-page extraction with Playwright + Mozilla Readability (handles JavaScript-heavy sites) |
| 📝 **Text Notes** | Paste or type custom notes directly as sources |
| 🔍 **Grounded Strict Mode** | AI answers using only your sources — every claim gets a citation like `[1]` |
| 🧠 **Creative AI Mode** | Bypasses retrieval and answers from the model's own training knowledge |
| 📌 **Citation Panel** | Click any citation to see the exact source chunk it came from |
| ⚡ **Quick Actions** | One-tap chips: Summarize, Key Concepts, Generate Quiz, Create Notes |
| 🎯 **Custom Instructions** | Per-workspace AI behavior: "Answer in Hindi", "Use bullet lists only", etc. |
| 🔒 **100% Local & Private** | No telemetry, no analytics, no cloud APIs required |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter Desktop App                  │
│     (Riverpod state • Markdown rendering • SSE stream)  │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP / Server-Sent Events
                         │ localhost:8000
┌────────────────────────▼────────────────────────────────┐
│                   FastAPI Backend                        │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  Extraction  │  │  Embeddings  │  │  RAG Retriever │  │
│  │  Pipelines   │  │  (ONNX GTE)  │  │  (FAISS index) │  │
│  └─────────────┘  └──────────────┘  └───────┬────────┘  │
│                                              │           │
│  ┌───────────────────────────────────────────▼────────┐  │
│  │              Ollama (local LLM)                    │  │
│  │         qwen2.5:1.5b (default) or any model        │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Storage**: Each workspace stores its data in `~/Library/Application Support/KivoWorkspace/` (macOS) or the platform equivalent. Raw source files are purged after processing — only the extracted text, vector embeddings, and SQLite database are retained.

---

## Enriched Citations & Context-Aware RAG (New)

The RAG engine is updated with advanced interactive metadata extraction and query optimization:

1. **Context-Aware Query Rewriting:**
   - Detects pronouns (e.g., *he*, *she*, *it*, *they*) in user prompts and executes a low-latency background co-reference resolution query against recent chat history turns.
   - Restores reference clarity before executing vector search queries, keeping the original question in the user-facing response payload.

2. **Enriched Citations:**
   - **PDF:** Collects page numbers (`pages`) from index metadata. Click page citations to open dynamic visual document preview layers.
   - **YouTube:** Captures video seconds (`start_times`) and formats timestamp links (`timestamp_url`) with `&t=X` parameter for immediate playhead seek.

3. **Dynamic PDF Page Renderer API:**
   - Served at `GET /workspaces/{workspace_id}/sources/{source_id}/pages/{page_num}`.
   - Uses PyMuPDF (`fitz`) to extract, render, and stream individual pages as fast PNG images on-the-fly, allowing instant preview tags (`<img src="...">`) in frontend.

4. **Startup Memory Warmup:**
   - Pre-warms the default Ollama model immediately at system start, and lazy-loads the GTE ONNX embedding model 6 seconds later to prevent memory conflict on Edge AI environments (like Jetson Nano).

---

## Installation (End Users)

> **Prerequisites:** [Ollama](https://ollama.com) must be installed and running, with at least one model pulled.

```bash
# Pull the default model first
ollama pull qwen2.5:1.5b
```

### macOS / Linux — One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/main/install.sh | bash
```

### Windows — PowerShell install

```powershell
irm https://raw.githubusercontent.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/main/install.ps1 | iex
```

Both scripts download the latest pre-built binary from [GitHub Releases](https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/releases), install it to the appropriate location, and create app shortcuts automatically.

### Manual Download

Download the latest release directly from the [Releases page](https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship/releases):

| Platform | Binary Installer File | Format |
|----------|----------------------|--------|
| **macOS (Apple Silicon)** | `KivoWorkspace-macOS-Silicon-1.1.0.dmg` | Native arm64 drag-and-drop installer |
| **macOS (Intel)** | `KivoWorkspace-macOS-Intel-1.1.0.dmg` | Native x86_64 drag-and-drop installer |
| **Windows x64** | `KivoWorkspace-Windows-1.1.0.exe` | Standalone executable |
| **Linux (Debian/Ubuntu)** | `KivoWorkspace-Linux-1.1.0.deb` | Debian Package installer |
| **Linux (RedHat/Fedora)** | `KivoWorkspace-Linux-1.1.0.rpm` | RPM Package installer |
| **Linux (Generic)** | `KivoWorkspace-Linux-1.1.0.AppImage` | Portable executable package |

---

## Edge & Headless Deployments (`start.sh`)

For local Linux development machines, headless servers, Google Colab, or low-power edge boards like the **NVIDIA Jetson Orin/Nano**, Kivo Workspace provides a premium interactive CLI launcher (`start.sh`). It hosts both the FastAPI backend and compiled Web UI on a single port (`8000`), resolving all CORS issues.

To launch, clone the repository and execute:
```bash
./start.sh
```

### 1. Testing on a Local Linux Machine
* Run `./start.sh` and select **Option 1** (`Start Kivo Workspace`).
* The launcher runs dependency checks silently, downloads any missing utilities, compiles Python packages behind clean spinners, and serves the app.
* Connect via:
  - **Local Browser:** `http://localhost:8000`
  - **Local LAN Network:** `http://<your-lan-ip>:8000` (ideal for remote device testing)

### 2. Testing on NVIDIA Jetson Orin/Nano (Edge AI)
* **Pre-requisite:** Ensure you have at least **4GB of SWAP space** active to avoid system locks under peak ingestion loads.
* Run `./start.sh` and choose **Option 1**.
* **Edge-Optimized Auto-Profiles:** The launcher automatically detects the `aarch64` architecture and configures:
  - `OLLAMA_NUM_PARALLEL=1` and `OLLAMA_KEEP_ALIVE=5m` (limits thread concurrency and auto-evicts idle weights after 5 minutes).
  - Capped active LLM model resident memory (unloads previous models instantly when swapping models to save RAM).
  - Quantized GTE ONNX embeddings (INT8) to drop memory footprint by 150MB.

### 3. Testing on Google Colab (Headless Tunnel)
* Upload the Kivo Workspace folder to your Google Colab instance.
* Run `!bash start.sh` in a notebook cell.
* **Headless Autopilot:** The script automatically detects the non-interactive Colab container and activates automation:
  - Downloads the Flutter SDK, builds the Web UI, installs and spins up the local Ollama background service with GPU exports.
  - Pulls `qwen2.5:1.5b` and establishes a secure **Cloudflare Quick Tunnel** to output a public evaluation link. Open the generated `https://*.trycloudflare.com` URL to launch!

---

## System Requirements

| Component | Requirement |
|-----------|-------------|
| **OS** | macOS 12+, Windows 10+, Ubuntu 20.04+ |
| **RAM** | 8 GB minimum (16 GB recommended for larger models) |
| **Disk** | 5 GB free (model weights + workspace data) |
| **Ollama** | Required — install from [ollama.com](https://ollama.com) |
| **FFmpeg** | Required for audio/video sources |
| **Tesseract** | Required for image OCR |

**Install system dependencies (macOS):**
```bash
brew install ffmpeg tesseract
```

**Install system dependencies (Ubuntu/Debian):**
```bash
sudo apt-get install -y ffmpeg tesseract-ocr
```

**Install system dependencies (Windows):**  
Install [FFmpeg](https://ffmpeg.org/download.html) and [Tesseract](https://github.com/UB-Mannheim/tesseract/wiki) and add both to your system PATH.

---

## For Developers

Want to run from source, modify the code, or contribute? See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full developer setup guide.

**Quick summary:**
```bash
# Clone the repo
git clone https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship.git
cd The-Threadrippers_edgeminds2026internship

# macOS/Linux: one script sets up everything and launches the app
./setup.sh

# Windows: PowerShell equivalent
.\setup.ps1
```

### macOS Intel Self-Hosted CI Builder Setup

The macOS Intel DMG is compiled on a local machine using GitHub's self-hosted runner program.

#### 1. Setup & Configuration (First Time Only)
1. In your GitHub repository, go to **Settings > Actions > Runners**.
2. Click **New self-hosted runner** and select **macOS** as the runner platform.
3. Follow the commands provided on the page to download, extract, and configure the runner package.
4. Run the config script with your repository URL and token:
   ```bash
   ./config.sh --url https://github.com/thepriyanshumishra/The-Threadrippers_edgeminds2026internship --token <YOUR_RUNNER_TOKEN>
   ```

#### 2. Starting/Managing the Runner Program
* **Foreground Mode** (runs in your current terminal session):
  ```bash
  ./run.sh
  ```
* **Background Service Mode** (runs continuously as a system daemon, highly recommended):
  ```bash
  # Install the background agent
  ./svc.sh install
  
  # Start the runner service
  ./svc.sh start
  
  # Check runner service status
  ./svc.sh status
  
  # Stop the runner service
  ./svc.sh stop
  ```

---

## Project Structure

```
KivoWorkspace/
├── frontend/                   # Flutter desktop app
│   ├── lib/
│   │   ├── features/           # Feature modules (workspace, chat, sources, settings)
│   │   ├── core/               # Theme, routing, shared widgets
│   │   └── main.dart
│   └── macos/ windows/ linux/  # Platform-specific build configs
│
├── backend/                    # FastAPI Python server
│   ├── app/
│   │   ├── api/routes/         # REST endpoints (workspaces, sources, chat, processing)
│   │   ├── core/               # RAG retriever, config, database
│   │   └── core/processors/    # Extraction pipelines (PDF, OCR, YouTube, audio, web)
│   ├── tests/                  # pytest test suite
│   ├── requirements.txt        # Production dependencies
│   ├── requirements-dev.txt    # Development/test dependencies
│   └── main.py                 # FastAPI app entry point
│
├── .github/workflows/          # CI/CD — auto-builds and publishes releases on git tag
├── install.sh / install.ps1    # End-user one-line installers
├── setup.sh / setup.ps1        # Developer source setup & launcher scripts
└── Docs/                       # Internal architecture docs (gitignored)
```

---

## Recommended Models

Kivo works with any model available in Ollama. Tested configurations:

| Model | Size | Use Case |
|-------|------|----------|
| `qwen2.5:1.5b` | ~1 GB | Default — fast, low RAM, good for constrained hardware |
| `qwen2.5:7b` | ~5 GB | Better reasoning, recommended if you have 16 GB RAM |
| `llama3.2:3b` | ~2 GB | Alternative lightweight option |
| `mistral:7b` | ~5 GB | Strong instruction following |

Change the active model from the **Settings** screen inside the app.

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first for development setup, code style, and PR guidelines.

**Quick steps:**
1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes and run tests: `cd backend && ./venv/bin/pytest`
4. Push and open a Pull Request

Please open a GitHub Issue before starting work on a major feature so we can align on the approach.

---

## License

Copyright © 2026 Kivo Workspace Contributors.

Licensed under the **Apache License, Version 2.0**. See [LICENSE](LICENSE) for the full text.

You are free to use, modify, and distribute this software under the terms of the Apache 2.0 license. Attribution is required when redistributing.
