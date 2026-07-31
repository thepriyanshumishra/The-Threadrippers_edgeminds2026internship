# 🚀 Kivo Workspace — Edge Intelligence RAG Platform

**Kivo Workspace** is a **100% offline, privacy-first, edge-optimized AI Retrieval-Augmented Generation (RAG) platform**. Designed for high-performance deployment on **NVIDIA Jetson (Orin Nano / Xavier)**, **macOS (Apple Silicon / Intel)**, and **Google Colab**, Kivo enables users to organize multi-modal sources (PDFs, Audio/Video, Web Scraping, YouTube, Text) and interact with them securely on-device without cloud API dependencies.

---

## ✨ Key Features

- 🔒 **3-Mode Grounded RAG Engine**:
  - **`Strict Mode`**: Strictly document-bounded. Refuses out-of-domain questions with zero hallucination.
  - **`Default Mode`** *(Recommended)*: Hybrid intelligence. Gives primary preference to workspace sources, and seamlessly uses general AI knowledge for uncovered questions.
  - **`Explore Mode`**: Pure AI chat bypassing document retrieval.
- 📍 **NotebookLM-Style Citation System**:
  - `SOURCES USED` section below every response with file icons, page numbers (`p. 3, 7`), timestamps (`1:23`), hover tooltips showing exact quoted snippets, and dynamic relevance progress bars (0-100%).
- ⚡ **Real-Time Edge Hardware Telemetry Badge**:
  - Live top navbar pill displaying memory footprint (`1.4/8.0 GB RAM`), ONNX INT8 quantized execution status, and local Ollama model health.
- 💬 **Conversational Memory (SQLite Persistence)**:
  - Multi-turn Q&A chat history is automatically persisted to workspace SQLite databases (`metadata.db`) and restored upon browser refresh.
- 📄 **1-Click Workspace & Notes Exporter**:
  - Download full workspace chat transcripts and study notes as clean Markdown (`.md`) reports.
- 🎵 **Multi-Modal Document Processing**:
  - PDF Text & Optical Character Recognition (OCR), Audio/Video Transcription via FFmpeg + Whisper, YouTube Video Scraping, and Web Page Content Extraction.

---

## 🛠️ Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────┐
│                        KIVO WORKSPACE EDGE UI                          │
│                Flutter Web SPA / PWA (Riverpod State)                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTP REST / SSE Stream
┌───────────────────────────────────▼────────────────────────────────────┐
│                       FASTAPI BACKEND ENGINE                           │
│  - SQLite RAG Cache & Conversational Memory (metadata.db)             │
│  - ONNX Quantized Embedding Pipeline (gte-multilingual-base)          │
│  - USearch Vector DB (768-dim Cosine Metric)                           │
│  - Post-Hoc Grounding & Dynamic Relevance Calculator                   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Local IPC / HTTP
┌───────────────────────────────────▼────────────────────────────────────┐
│                        LOCAL OLLAMA LLM SERVICE                        │
│                qwen2.5:0.5b / qwen2.5:1.5b (INT4/INT8)                 │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start (Single Command)

Spin up the entire platform (dependencies, embedding warmup, web build compilation, and backend server) with a single command:

```bash
./start.sh
```

Select **Option [1]** to launch Kivo Workspace. The interactive CLI will display:
- Local URL: `http://localhost:8000`
- Network URL: `http://<your-ip>:8000`
- Public Link: `https://<random>.trycloudflare.com` (via Cloudflare Quick Tunnel)

---

## 📁 Repository Structure

```
.
├── backend/                  # FastAPI Python Backend Service
│   ├── app/
│   │   ├── api/routes/       # REST Routes (chat, sources, processing, system, exporter)
│   │   ├── core/             # RAG Retriever, Vector DB, Database, Embeddings
│   │   └── models/           # Pydantic Schemas
│   └── main.py               # FastAPI App Entrypoint & Static Server
├── frontend/                 # Flutter Web SPA Frontend
│   ├── lib/                  # Dart UI components, screens, providers, widgets
│   └── build/web/            # Pre-compiled Production Web UI
├── docs/                     # Documentation & Deployment Guides
│   ├── how_to_run.md         # Detailed setup instructions for Mac, Jetson & Colab
│   └── how_to_run.pdf        # PDF guide for judges and evaluators
├── start.sh                  # Interactive CLI Launcher
├── clean.sh                  # Workspace Reset & Cache Purging Script
└── README.md                 # Project Overview & Architecture
```

---

## 📖 Deployment Documentation

For step-by-step instructions on deploying Kivo Workspace across **macOS**, **NVIDIA Jetson**, and **Google Colab**, refer to:
- 📖 [docs/how_to_run.md](file:///Users/thedarkpcm/Desktop/Kivo%20Workspace%20Jetson/docs/how_to_run.md)
- 📄 [docs/how_to_run.pdf](file:///Users/thedarkpcm/Desktop/Kivo%20Workspace%20Jetson/docs/how_to_run.pdf)
