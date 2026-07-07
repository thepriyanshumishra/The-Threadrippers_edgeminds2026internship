# app/core/ollama_manager.py
# Purpose: Manages Ollama memory footprint by ensuring only one model is loaded at a time.

import httpx
import logging
from app.core.config import settings

logger = logging.getLogger("kivo.ollama_manager")

async def ensure_only_model(target_model: str, ollama_url: str = None) -> None:
    """
    Checks the currently loaded models in Ollama and unloads any model 
    that is not the target_model, ensuring only one model resides in memory.
    """
    url = ollama_url or settings.ollama_base_url
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # 1. Get currently loaded models
            ps_res = await client.get(f"{url}/api/ps")
            if ps_res.status_code != 200:
                logger.warning(f"Ollama ps call failed: {ps_res.status_code}")
                return
                
            data = ps_res.json()
            loaded_models = data.get("models", [])
            
            # Clean target name for matching (e.g. "qwen2.5:1.5b")
            clean_target = target_model.strip()
            
            for m in loaded_models:
                name = m.get("name", "")
                # If the loaded model name is not our target model
                if name and name != clean_target and name != f"{clean_target}:latest":
                    logger.info(f"Unloading model '{name}' from Ollama memory to save RAM...")
                    # Send keep_alive: 0 to unload
                    unload_res = await client.post(
                        f"{url}/api/chat",
                        json={"model": name, "keep_alive": 0}
                    )
                    if unload_res.status_code == 200:
                        logger.info(f"Successfully unloaded '{name}'")
                    else:
                        # Fallback try generate api
                        await client.post(
                            f"{url}/api/generate",
                            json={"model": name, "keep_alive": 0}
                        )
    except Exception as e:
        logger.error(f"Error managing loaded Ollama models: {e}")
