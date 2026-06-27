# main.py
# Purpose: FastAPI application entry point for Kivo Workspace backend.
# Inputs: HTTP requests from the Flutter frontend.
# Outputs: JSON responses.
# Responsibilities: Creates FastAPI app, configures CORS, registers routers,
#                   ensures storage directories exist on startup.

import os
import sys
import shutil
import httpx
from pathlib import Path

# Detect local virtual environment and inject its site-packages into sys.path
def inject_local_env():
    home = Path.home()
    env_dir = home / ".kivo_workspace" / "env"
    if env_dir.exists():
        site_packages = None
        if os.name == "nt":  # Windows
            sp = env_dir / "Lib" / "site-packages"
            if sp.exists():
                site_packages = sp
        else:  # macOS/Linux
            lib_dir = env_dir / "lib"
            if lib_dir.exists():
                for python_dir in lib_dir.iterdir():
                    if python_dir.is_dir() and python_dir.name.startswith("python"):
                        sp = python_dir / "site-packages"
                        if sp.exists():
                            site_packages = sp
                            break
        if site_packages:
            sys.path.insert(0, str(site_packages))
            print(f"[BOOTSTRAP] Injected local dependencies from: {site_packages}")

inject_local_env()
# Allow ONNX runtime and PyTorch to use multiple CPU threads for faster embedding.
# Previously locked to 1 (to avoid OpenMP/FAISS conflict) but FAISS import order
# handles that now — letting the embedding model use up to 8 threads.
import multiprocessing as _mp
_cpu_count = _mp.cpu_count()
_embed_threads = str(min(8, max(1, _cpu_count // 2)))  # Half of cores, max 8
os.environ["OMP_NUM_THREADS"] = _embed_threads
os.environ["MKL_NUM_THREADS"] = _embed_threads
os.environ["OPENBLAS_NUM_THREADS"] = _embed_threads
os.environ["VECLIB_MAXIMUM_THREADS"] = _embed_threads
os.environ["NUMEXPR_NUM_THREADS"] = _embed_threads
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
os.environ["ONNXRUNTIME_NUM_THREADS"] = _embed_threads

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# Attach RotatingFileHandler for uvicorn.log rotation (max 10MB, 2 files)
from logging.handlers import RotatingFileHandler
try:
    log_file = Path("uvicorn.log").absolute()
    file_handler = RotatingFileHandler(str(log_file), maxBytes=10 * 1024 * 1024, backupCount=1)
    file_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s", "%Y-%m-%d %H:%M:%S"))
    file_handler.setLevel(logging.INFO)
    logging.getLogger().addHandler(file_handler)
    
    for uvicorn_logger in ["uvicorn", "uvicorn.error", "uvicorn.access"]:
        logging.getLogger(uvicorn_logger).addHandler(file_handler)
except Exception as log_err:
    print(f"[LOG SETUP ERROR] Failed to setup RotatingFileHandler: {log_err}")

logger = logging.getLogger("kivo")


def run_diagnostics():
    """Runs non-blocking startup sanity checks for dependencies."""
    logger.info("--- Starting Kivo Diagnostics ---")
    
    # 1. Check FFmpeg
    ffmpeg_path = shutil.which("ffmpeg")
    if ffmpeg_path:
        logger.info(f"[DIAGNOSTIC] FFmpeg binary found: {ffmpeg_path}")
    else:
        logger.warning("[DIAGNOSTIC WARNING] FFmpeg was NOT found on system PATH. Audio transcription and YouTube processing will fail. Please install ffmpeg.")

    # 2. Check Tesseract
    tesseract_path = shutil.which("tesseract")
    if tesseract_path:
        logger.info(f"[DIAGNOSTIC] Tesseract OCR binary found: {tesseract_path}")
    else:
        logger.warning("[DIAGNOSTIC WARNING] Tesseract was NOT found on system PATH. Image OCR processing will fail. Please install tesseract-ocr.")

    # 3. Check Ollama
    try:
        ollama_url = f"{settings.ollama_base_url}/api/tags"
        response = httpx.get(ollama_url, timeout=3)
    except Exception as e:
        logger.warning(f"[DIAGNOSTIC WARNING] Could not connect to Ollama service at {settings.ollama_base_url}. Attempting to start Ollama service...")
        try:
            import subprocess
            import time
            ollama_path = shutil.which("ollama")
            if not ollama_path and os.path.exists("/Applications/Ollama.app/Contents/Resources/ollama"):
                ollama_path = "/Applications/Ollama.app/Contents/Resources/ollama"

            if ollama_path:
                subprocess.Popen([ollama_path, "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                logger.info("[DIAGNOSTIC] Started Ollama service in background. Waiting 1.5 seconds for it to bind...")
                time.sleep(1.5)
                try:
                    response = httpx.get(ollama_url, timeout=3)
                except Exception:
                    response = None
            else:
                logger.warning("[DIAGNOSTIC WARNING] Ollama executable not found on system PATH or Applications folder.")
                response = None
        except Exception as start_err:
            logger.error(f"[DIAGNOSTIC ERROR] Failed to auto-start Ollama: {start_err}")
            response = None

    if response and response.status_code == 200:
        models_data = response.json()
        models_list = [m.get("name") for m in models_data.get("models", [])]
        logger.info(f"[DIAGNOSTIC] Ollama service is active. Available models: {models_list}")
        
        # Check default model
        default_model = settings.ollama_default_model
        if default_model in models_list or any(default_model in m for m in models_list):
            logger.info(f"[DIAGNOSTIC] Default LLM model '{default_model}' is available in Ollama.")
        else:
            logger.warning(f"[DIAGNOSTIC WARNING] Default LLM model '{default_model}' is NOT pulled in Ollama. Please run: ollama pull {default_model}")
    else:
        logger.warning(f"[DIAGNOSTIC WARNING] Ollama service could not be started or is not reachable.")
        
    logger.info("--- Diagnostics Completed ---")


# --- Startup / Shutdown Lifecycle ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan handler.
    Runs setup tasks on startup and cleanup on shutdown.
    """
    # Ensure storage directories exist
    settings.storage_dir.mkdir(parents=True, exist_ok=True)
    settings.workspaces_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Storage directories verified.")
    
    # Run startup diagnostic checks
    run_diagnostics()
    
    logger.info(f"Kivo Workspace API v{settings.app_version} started.")
    logger.info(f"Ollama target: {settings.ollama_base_url}")
    logger.info(f"Default model: {settings.ollama_default_model}")

    import asyncio
    async def warm_up_embedding_model():
        try:
            await asyncio.sleep(6)  # Give Ollama 6s to bind GPU memory first
            logger.info("[Warmup] Starting background embedding model warming...")
            from app.core.processors.embeddings import get_embedding_model
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, get_embedding_model)
            logger.info("[Warmup] Background embedding model warmed up successfully.")
        except Exception as e:
            logger.error(f"[Warmup] Embedding model warming failed: {e}")

    asyncio.create_task(warm_up_embedding_model())

    yield

    logger.info("Kivo Workspace API shutting down.")


# --- FastAPI Application ---
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Edge-first AI Knowledge Workspace Backend",
    lifespan=lifespan,
)


# --- CORS Middleware ---
# Allows Flutter web app to communicate with the API from:
#   - Local desktop app (file://)
#   - Localhost browser dev
#   - Public tunnels: ngrok, Cloudflare Quick Tunnel, Localtunnel
app.add_middleware(
    CORSMiddleware,
    allow_origins=["file://"],
    allow_origin_regex=(
        r"https?://(localhost|127\.0\.0\.1)(:\d+)?"       # Local dev
        r"|https://[a-zA-Z0-9\-]+\.ngrok-free\.app"       # ngrok v3 free tunnels
        r"|https://[a-zA-Z0-9\-]+\.ngrok\.io"             # ngrok legacy tunnels
        r"|https://[a-zA-Z0-9\-]+\.trycloudflare\.com"    # Cloudflare Quick Tunnels
        r"|https://[a-zA-Z0-9\-]+\.loca\.lt"              # Localtunnel
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Static Files / SPA Directory Resolution ---
from fastapi.responses import FileResponse

base_path = Path(__file__).parent
web_dir = base_path / "frontend" / "build" / "web"
if not web_dir.exists():
    # Support sibling directory for local development
    web_dir = base_path.parent / "frontend" / "build" / "web"
if not web_dir.exists():
    web_dir = base_path / "web"

if getattr(sys, "frozen", False):
    # If running inside PyInstaller bundle, look in sys._MEIPASS first
    meipass_web = Path(sys._MEIPASS) / "web"
    if meipass_web.exists():
        web_dir = meipass_web
    else:
        exe_dir = Path(sys.executable).parent
        if (exe_dir / "web").exists():
            web_dir = exe_dir / "web"


# --- Core Routes ---
@app.get("/", tags=["Root"])
async def root():
    """API root — returns index.html if frontend is built, otherwise basic API info."""
    index_path = web_dir / "index.html"
    if web_dir.exists() and index_path.exists():
        return FileResponse(index_path)
    return {
        "app": settings.app_name,
        "version": settings.app_version,
        "status": "running",
    }


@app.get("/health", tags=["Health"])
async def health_check():
    """
    Health check endpoint.
    Used by the Flutter frontend to verify the backend is reachable.
    """
    return {"status": "ok"}


@app.get("/system/diagnostics", tags=["Health"])
async def system_diagnostics():
    """
    Runs real-time diagnostic checks on dependencies and environment resources.
    Returns status, version, and specific metadata metrics for:
    - Tesseract OCR
    - FFmpeg
    - Ollama LLM
    - Database (SQLite & FAISS)
    - Local storage
    """
    import time
    import re

    # 1. Tesseract Check
    tesseract_path = shutil.which("tesseract")
    tesseract_status = "Online" if tesseract_path else "Offline"
    tesseract_version = "Not Found"
    tesseract_latency = "N/A"
    
    if tesseract_path:
        try:
            import subprocess
            t1 = time.time()
            result = subprocess.run([tesseract_path, "--version"], capture_output=True, text=True, timeout=1.5)
            latency_ms = int((time.time() - t1) * 1000)
            tesseract_latency = f"{latency_ms}ms"
            
            # Parse version
            first_line = result.stdout.split("\n")[0] if result.stdout else ""
            match = re.search(r"tesseract (\S+)", first_line)
            if match:
                tesseract_version = f"v{match.group(1)}"
            else:
                tesseract_version = "vUnknown"
        except Exception:
            tesseract_status = "Warning"
            tesseract_version = "Error checking version"
            
    # 2. FFmpeg Check
    ffmpeg_path = shutil.which("ffmpeg")
    ffmpeg_status = "Ready" if ffmpeg_path else "Offline"
    ffmpeg_version = "Not Found"
    
    if ffmpeg_path:
        try:
            import subprocess
            result = subprocess.run([ffmpeg_path, "-version"], capture_output=True, text=True, timeout=1.5)
            first_line = result.stdout.split("\n")[0] if result.stdout else ""
            match = re.search(r"ffmpeg version (\S+)", first_line)
            if match:
                ffmpeg_version = f"v{match.group(1)}"
            else:
                ffmpeg_version = "vUnknown"
        except Exception:
            ffmpeg_version = "vUnknown"
            
    # 3. Ollama Check
    ollama_status = "Offline"
    ollama_version = "N/A"
    ollama_models = []
    default_model = settings.ollama_default_model
    is_model_available = False
    
    try:
        # Check /api/tags
        response = httpx.get(f"{settings.ollama_base_url}/api/tags", timeout=2)
        if response.status_code == 200:
            ollama_status = "Online"
            data = response.json()
            models = data.get("models", [])
            ollama_models = [m.get("name") for m in models]
            
            # Check version
            ver_resp = httpx.get(f"{settings.ollama_base_url}/api/version", timeout=1)
            if ver_resp.status_code == 200:
                ollama_version = f"v{ver_resp.json().get('version', 'unknown')}"
                
            # Check model availability
            is_model_available = any(default_model in m for m in ollama_models)
    except Exception:
        pass
        
    # 4. Database Check (SQLite + FAISS)
    import sqlite3
    db_status = "Connected"
    collections_count = 0
    total_embeddings = 0
    engine_version = "sqlite unknown"
    
    try:
        engine_version = f"sqlite v{sqlite3.sqlite_version}"
        try:
            import faiss
            engine_version += f", faiss v{faiss.__version__}"
        except Exception:
            pass
            
        workspaces_dir = settings.workspaces_dir
        if workspaces_dir.exists():
            for ws_path in workspaces_dir.iterdir():
                if ws_path.is_dir() and (ws_path / "metadata.json").exists():
                    collections_count += 1
                    db_path = ws_path / "metadata.db"
                    if db_path.exists():
                        try:
                            conn = sqlite3.connect(db_path)
                            cursor = conn.cursor()
                            cursor.execute("SELECT COUNT(*) FROM child_chunks")
                            count = cursor.fetchone()[0]
                            total_embeddings += count
                            conn.close()
                        except Exception:
                            pass
    except Exception:
        db_status = "Error"
        
    # 5. Local Storage Check
    storage_path = settings.storage_dir.absolute()
    storage_status = "Ready"
    percent = 0.0
    used_gb = 0.0
    free_gb = 0.0
    total_gb = 0.0
    
    try:
        usage = shutil.disk_usage(storage_path)
        total_gb = round(usage.total / (1024**3), 1)
        used_gb = round(usage.used / (1024**3), 1)
        free_gb = round(usage.free / (1024**3), 1)
        percent = round((usage.used / usage.total) * 100, 1)
    except Exception:
        storage_status = "Error"
        
    return {
        "tesseract": {
            "status": tesseract_status,
            "version": tesseract_version,
            "metadata": {
                "latency": tesseract_latency
            }
        },
        "ffmpeg": {
            "status": ffmpeg_status,
            "version": ffmpeg_version,
            "metadata": {
                "queue": "0 items"
            }
        },
        "ollama": {
            "status": ollama_status,
            "version": ollama_version,
            "metadata": {
                "default_model": default_model,
                "is_model_available": is_model_available,
                "available_models": ollama_models
            }
        },
        "database": {
            "status": db_status,
            "version": engine_version,
            "metadata": {
                "engine": "SQLite & FAISS",
                "collections": collections_count,
                "total_embeddings": total_embeddings
            }
        },
        "storage": {
            "status": storage_status,
            "version": "local",
            "metadata": {
                "path": "<local app data>",
                "percent": percent,
                "used_gb": used_gb,
                "free_gb": free_gb,
                "total_gb": total_gb
            }
        }
    }



# --- Router Registration ---
from app.api.routes.workspaces import router as workspaces_router
from app.api.routes.sources import router as sources_router
from app.api.routes.processing import router as processing_router
from app.api.routes.chat import router as chat_router
from app.api.routes.universal_chat import router as universal_chat_router
from app.api.routes.system import router as system_router

app.include_router(workspaces_router, prefix="/workspaces", tags=["Workspaces"])
app.include_router(sources_router, prefix="/workspaces/{workspace_id}/sources", tags=["Sources"])
app.include_router(processing_router, prefix="/workspaces/{workspace_id}/processing", tags=["Processing"])
app.include_router(chat_router, prefix="/workspaces/{workspace_id}/chat", tags=["Chat"])
app.include_router(universal_chat_router, prefix="/universal-chat", tags=["Universal Chat"])
app.include_router(system_router, prefix="/system", tags=["System"])


from app.core.exceptions import DepsRequiredException
from fastapi.responses import JSONResponse

@app.exception_handler(DepsRequiredException)
async def deps_required_exception_handler(request, exc: DepsRequiredException):
    DEFAULT_SIZES = {
        "playwright": 50.0,
        "chromium": 280.0,
        "curl_cffi": 5.0,
        "faster-whisper": 80.0,
        "whisper-model-base": 148.0,
        "rapidocr-onnxruntime": 15.0,
        "ocr-model-english": 15.0,
    }
    sizes = {}
    total_mb = 0.0
    for dep in exc.deps:
        size = DEFAULT_SIZES.get(dep, 10.0)
        sizes[dep] = size
        total_mb += size
        if dep == "playwright":
            sizes["chromium"] = DEFAULT_SIZES["chromium"]
            total_mb += DEFAULT_SIZES["chromium"]
        elif dep == "faster-whisper":
            sizes["whisper-model-base"] = DEFAULT_SIZES["whisper-model-base"]
            total_mb += DEFAULT_SIZES["whisper-model-base"]
        elif dep == "rapidocr-onnxruntime":
            sizes["ocr-model-english"] = DEFAULT_SIZES["ocr-model-english"]
            total_mb += DEFAULT_SIZES["ocr-model-english"]

    return JSONResponse(
        status_code=400,
        content={
            "action": "deps_required",
            "deps": exc.deps,
            "sizes_mb": sizes,
            "total_mb": total_mb,
            "message": exc.message
        }
    )


# --- Static Files / SPA Serving ---
from fastapi.staticfiles import StaticFiles

if web_dir.exists():
    logger.info(f"Serving Flutter frontend from static directory: {web_dir}")
    
    # Mount the assets directory separately to ensure files are served directly
    assets_dir = web_dir / "assets"
    if assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.get("/{catchall:path}")
    async def serve_spa(catchall: str):
        # Prevent accessing API routes through catchall
        if catchall.startswith(("workspaces", "universal-chat", "health", "system")):
            return {"error": "Not Found"}
            
        # Resolve real path to prevent directory traversal attacks
        try:
            resolved_path = (web_dir / catchall).resolve()
            if resolved_path.is_file() and resolved_path.is_relative_to(web_dir.resolve()):
                return FileResponse(resolved_path)
        except Exception:
            pass
            
        # Fallback to index.html for client-side routing (SPA)
        index_path = web_dir / "index.html"
        if index_path.exists():
            return FileResponse(index_path)
            
        return {"error": "Frontend assets not found"}
else:
    logger.warning(f"Frontend static directory NOT found at {web_dir}. Single-port web serving is disabled.")


if __name__ == "__main__":
    import uvicorn
    import argparse
    import webbrowser
    import threading
    import time
    import multiprocessing

    # CRITICAL: Required on macOS/Windows when frozen by PyInstaller to prevent
    # the app from infinitely re-spawning child processes on startup.
    multiprocessing.freeze_support()

    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--host", type=str, default="127.0.0.1")
    args = parser.parse_args()

    # Find a free port starting from the requested one
    import socket
    def _find_free_port(host: str, start_port: int, tries: int = 5) -> int:
        for port in range(start_port, start_port + tries):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.bind((host, port))
                return port
            except OSError:
                logger.warning(f"Port {port} is already in use, trying {port + 1}...")
        return start_port  # Fall back to original; uvicorn will surface the error

    actual_port = _find_free_port(args.host, args.port)
    if actual_port != args.port:
        logger.info(f"Port {args.port} was in use. Using port {actual_port} instead.")

    # If packaged/run in production, open a native webview window
    if getattr(sys, "frozen", False):
        import webview

        def start_server():
            try:
                uvicorn.run(app, host=args.host, port=actual_port, log_level="info")
            except Exception as fatal:
                logger.critical(f"Kivo Workspace server failed to start: {fatal}")
                crash_log = Path.home() / "kivo_crash.log"
                try:
                    import traceback
                    with open(crash_log, "w") as f:
                        f.write("Kivo Workspace crashed on startup:\n")
                        traceback.print_exc(file=f)
                    logger.info(f"Crash log written to: {crash_log}")
                except Exception:
                    pass
                sys.exit(1)

        # Run uvicorn in a daemon thread so it runs in background
        server_thread = threading.Thread(target=start_server, daemon=True)
        server_thread.start()

        # Let the main thread launch the pywebview window
        logger.info(f"Launching native desktop window for Kivo Workspace on port {actual_port}...")
        try:
            window = webview.create_window(
                "Kivo Workspace",
                f"http://{args.host}:{actual_port}",
                width=1280,
                height=800,
                min_size=(1024, 768)
            )
            webview.start()
            logger.info("Native window closed. Exiting application.")
            sys.exit(0)
        except Exception as webview_err:
            logger.error(f"Failed to start pywebview: {webview_err}. Falling back to default browser...")
            try:
                webbrowser.open(f"http://{args.host}:{actual_port}")
            except Exception as e:
                logger.error(f"Failed to open browser: {e}")
            # Keep main thread alive since uvicorn is in a daemon thread
            server_thread.join()
    else:
        logger.info(f"Starting Kivo Workspace server in development mode at http://{args.host}:{actual_port}")
        try:
            uvicorn.run(app, host=args.host, port=actual_port)
        except Exception as fatal:
            logger.critical(f"Kivo Workspace server failed to start: {fatal}")
            sys.exit(1)





