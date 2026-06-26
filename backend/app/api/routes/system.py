# app/api/routes/system.py
# Purpose: System diagnostics, settings persistence, and Ollama proxying for web-served client.

import os
import sys
import platform
import shutil
import json
import logging
import httpx
from pathlib import Path
from typing import Any, Dict
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from app.core.config import settings

logger = logging.getLogger("kivo.system")
router = APIRouter()

CONFIG_FILE = settings.storage_dir.parent / "config.json"

def get_ram_gb() -> float:
    try:
        if os.name == "nt":  # Windows
            import subprocess
            res = subprocess.run(["wmic", "ComputerSystem", "get", "TotalPhysicalMemory"], capture_output=True, text=True, timeout=1.5)
            lines = res.stdout.strip().split("\n")
            if len(lines) > 1:
                bytes_val = int(lines[1].strip())
                return bytes_val / (1024**3)
        elif sys.platform == "darwin":  # macOS
            import subprocess
            res = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=1.5)
            bytes_val = int(res.stdout.strip())
            return bytes_val / (1024**3)
        else:  # Linux
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        kb_val = int(line.split()[1])
                        return kb_val / (1024 * 1024)
    except Exception as e:
        logger.warning(f"Failed to query system RAM: {e}")
    return 8.0  # Fallback

@router.get("/specs")
async def get_system_specs():
    """Returns local system specs (CPU, RAM, Disk) to the web UI."""
    try:
        cores = os.cpu_count() or 4
        ram_gb = get_ram_gb()
        
        storage_path = settings.storage_dir.absolute()
        usage = shutil.disk_usage(storage_path)
        free_gb = usage.free / (1024**3)
        
        # CPU vs GPU Acceleration Detection
        gpu_accelerated = False
        if platform.system().lower() == "darwin":
            # Apple Silicon macs have Metal
            gpu_accelerated = platform.machine() == "arm64"
        else:
            # Check for NVIDIA
            gpu_accelerated = shutil.which("nvidia-smi") is not None

        return {
            "os": platform.system().lower(),
            "cores": str(cores),
            "arch": platform.machine(),
            "ram": f"{ram_gb:.1f} GB",
            "ramValue": str(ram_gb),
            "disk": f"{free_gb:.1f} GB Free",
            "diskValue": str(free_gb),
            "gpu": "Hardware Accelerated (GPU/Metal)" if gpu_accelerated else "CPU Only",
            "gpuValue": str(gpu_accelerated).lower(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch system specifications: {e}")

@router.get("/settings")
async def get_settings():
    """Retrieve global application settings."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to read config file: {e}")
    return {}

@router.post("/settings")
async def save_settings(data: Dict[str, Any]):
    """Persist global application settings."""
    try:
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        
        existing = {}
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, "r") as f:
                    existing = json.load(f)
            except Exception:
                pass
                
        existing.update(data)
        with open(CONFIG_FILE, "w") as f:
            json.dump(existing, f, indent=2)
        return {"status": "saved"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to save settings: {e}")

@router.get("/ollama/tags")
async def get_ollama_tags():
    """Proxy tag check to Ollama server, resolving CORS for the web client."""
    async with httpx.AsyncClient(timeout=3.0) as client:
        try:
            response = await client.get(f"{settings.ollama_base_url}/api/tags")
            return response.json()
        except Exception as e:
            return {"models": [], "error": str(e)}

@router.post("/ollama/pull")
async def pull_ollama_model(payload: Dict[str, Any]):
    """Proxy streaming pull to Ollama server."""
    model_name = payload.get("name")
    if not model_name:
        raise HTTPException(status_code=400, detail="Model name is required")
        
    async def stream_generator():
        # Prevent hanging on stalled connections with a 20-second read timeout
        timeout = httpx.Timeout(20.0, connect=10.0, read=20.0, write=20.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                async with client.stream(
                    "POST",
                    f"{settings.ollama_base_url}/api/pull",
                    json={"name": model_name}
                ) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                logger.error(f"Ollama pull stream error or timeout: {e}")
                yield json.dumps({"error": f"Connection stalled: {str(e)}"}).encode("utf-8")

    return StreamingResponse(stream_generator(), media_type="application/x-ndjson")

@router.delete("/ollama/delete")
async def delete_ollama_model(payload: Dict[str, Any]):
    """Proxy deletion request to Ollama server."""
    model_name = payload.get("name")
    if not model_name:
        raise HTTPException(status_code=400, detail="Model name is required")
        
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            request = client.build_request(
                "DELETE",
                f"{settings.ollama_base_url}/api/delete",
                json={"name": model_name}
            )
            response = await client.send(request)
            if response.status_code == 200:
                return {"status": "success"}
            else:
                raise HTTPException(status_code=response.status_code, detail="Failed to delete model")
        except Exception as e:
            raise HTTPException(status_code=500, detail=str(e))
