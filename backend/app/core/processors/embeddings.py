# app/core/processors/embeddings.py
# Purpose: Local text embedding generation pipeline.
# Responsibilities:
#   1. Loads Alibaba-NLP/gte-multilingual-base model once (singleton pattern).
#   2. Auto-detects acceleration (MPS for Apple Silicon, CUDA for GPU, CPU fallback).
#   3. Generates high-accuracy multilingual embeddings for text chunks.
#   4. Cache vectors to disk as .npy files to allow incremental updates.

import logging
from pathlib import Path
from typing import Dict, Any, List
import json
import numpy as np

from app.core.config import settings

logger = logging.getLogger("kivo.processors.embeddings")

# Singleton instance of the model to avoid loading 610MB model weights repeatedly
_model_instance = None

class ONNXEmbeddingModel:
    def __init__(self, model_path: str, tokenizer_name: str = "Alibaba-NLP/gte-multilingual-base"):
        logger.info(f"Initializing ONNX Inference Session from: {model_path}")
        from transformers import AutoTokenizer
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_name, trust_remote_code=True)
        
        # Select best execution provider
        import onnxruntime as ort
        import os
        available_providers = ort.get_available_providers()
        # CoreMLExecutionProvider has compatibility issues with dynamic INT8 quantized NLP models, so we exclude it.
        preferred_providers = ["CUDAExecutionProvider", "DirectMLExecutionProvider", "CPUExecutionProvider"]
        providers = [p for p in preferred_providers if p in available_providers]
        
        logger.info(f"Available ONNX Execution Providers: {available_providers}")
        logger.info(f"Selected ONNX Execution Providers: {providers}")
        
        # Configure session options for multi-threaded CPU inference
        import multiprocessing
        num_threads = min(8, max(1, multiprocessing.cpu_count() // 2))
        sess_options = ort.SessionOptions()
        sess_options.intra_op_num_threads = num_threads   # threads within a single op
        sess_options.inter_op_num_threads = num_threads   # threads across parallel ops
        sess_options.execution_mode = ort.ExecutionMode.ORT_PARALLEL
        logger.info(f"ONNX session using {num_threads} threads (intra+inter).")
        
        self.session = ort.InferenceSession(model_path, sess_options=sess_options, providers=providers)

    def encode(
        self,
        sentences: List[str] | str,
        batch_size: int = 16,
        show_progress_bar: bool = False,
        normalize_embeddings: bool = True
    ) -> np.ndarray:
        if isinstance(sentences, str):
            sentences = [sentences]
            
        all_embeddings = []
        for i in range(0, len(sentences), batch_size):
            batch = sentences[i : i + batch_size]
            
            # Tokenize batch
            inputs = self.tokenizer(
                batch,
                padding=True,
                truncation=True,
                max_length=512,
                return_tensors="np"
            )
            
            # Prepare inputs for ONNX session
            ort_inputs = {
                "input_ids": inputs["input_ids"],
                "attention_mask": inputs["attention_mask"]
            }
            
            # Run inference
            ort_outputs = self.session.run(None, ort_inputs)
            last_hidden_state = ort_outputs[0]  # shape: [batch, seq_len, hidden_dim]
            
            # CLS pooling: take embedding of the first token (index 0)
            cls_embeddings = last_hidden_state[:, 0, :]
            
            # Normalize embeddings
            if normalize_embeddings:
                norms = np.linalg.norm(cls_embeddings, axis=1, keepdims=True)
                # Avoid division by zero
                cls_embeddings = np.where(norms > 0, cls_embeddings / norms, cls_embeddings)
                
            all_embeddings.append(cls_embeddings)
            
        return np.vstack(all_embeddings)

def get_embedding_model():
    """
    Lazy-loads and caches the quantized GTE model.
    If the quantized ONNX file is not found, automatically compiles it on CPU.
    """
    global _model_instance
    if _model_instance is not None:
        return _model_instance

    models_dir = settings.storage_dir / "models"
    models_dir.mkdir(parents=True, exist_ok=True)
    quant_onnx_path = models_dir / "gte_multilingual_base_quantized.onnx"

    if not quant_onnx_path.exists():
        logger.info("Quantized GTE ONNX model not found. Attempting to download pre-compiled model...")
        download_url = "https://huggingface.co/onnx-community/gte-multilingual-base/resolve/main/onnx/model_quantized.onnx"
        download_success = False
        try:
            import httpx
            with httpx.Client(follow_redirects=True, timeout=300.0) as client:
                logger.info(f"Downloading pre-compiled GTE ONNX model from: {download_url}")
                temp_download_path = quant_onnx_path.with_suffix(".tmp")
                with open(temp_download_path, "wb") as f:
                    with client.stream("GET", download_url) as response:
                        response.raise_for_status()
                        for chunk in response.iter_bytes(chunk_size=8192):
                            f.write(chunk)
                temp_download_path.rename(quant_onnx_path)
                logger.info("GTE ONNX model downloaded and saved successfully.")
                download_success = True
        except Exception as dl_err:
            logger.warning(f"Failed to download pre-compiled GTE model: {dl_err}. Falling back to local conversion...")

        if not download_success:
            logger.info("Starting local automatic conversion...")
            try:
                import torch
                from sentence_transformers import SentenceTransformer
                from onnxruntime.quantization import quantize_dynamic, QuantType
                
                temp_onnx_path = models_dir / "gte_multilingual_base_temp.onnx"
                
                logger.info("Loading PyTorch model on CPU for tracing...")
                model = SentenceTransformer("Alibaba-NLP/gte-multilingual-base", trust_remote_code=True, device="cpu")
                auto_model = model[0].auto_model
                tokenizer = model[0].tokenizer
                auto_model.eval()
                
                # Trace with dummy input
                text = "This is a test sentence for ONNX export."
                inputs = tokenizer(text, return_tensors="pt")
                
                logger.info("Exporting to FP32 ONNX graph...")
                with torch.no_grad():
                    torch.onnx.export(
                        auto_model,
                        (inputs["input_ids"].cpu(), inputs["attention_mask"].cpu()),
                        str(temp_onnx_path),
                        input_names=["input_ids", "attention_mask"],
                        output_names=["last_hidden_state"],
                        dynamic_axes={
                            "input_ids": {0: "batch_size", 1: "sequence_length"},
                            "attention_mask": {0: "batch_size", 1: "sequence_length"},
                            "last_hidden_state": {0: "batch_size", 1: "sequence_length"}
                        },
                        opset_version=14,
                        do_constant_folding=True
                    )
                    
                logger.info("Quantizing ONNX model to INT8...")
                quantize_dynamic(
                    model_input=str(temp_onnx_path),
                    model_output=str(quant_onnx_path),
                    weight_type=QuantType.QInt8
                )
                
                # Clean up the large temp FP32 file
                if temp_onnx_path.exists():
                    temp_onnx_path.unlink()
                    logger.info("Cleaned up temporary FP32 ONNX model file.")
                    
                logger.info("GTE ONNX quantization completed successfully.")
            except ImportError as import_err:
                logger.error(
                    f"[Embeddings] Optional packages (torch/sentence_transformers) not available "
                    f"for ONNX auto-conversion: {import_err}. "
                    f"Run the Kivo setup script to install them, or place a pre-built ONNX file at: {quant_onnx_path}"
                )
                return None
            except Exception as export_err:
                logger.error(f"[Embeddings] Failed to auto-export GTE model to ONNX: {export_err}")
                return None

    _model_instance = ONNXEmbeddingModel(str(quant_onnx_path))
    return _model_instance


class EmbeddingProcessor:
    def __init__(self):
        pass

    def process(self, workspace_id: str, source_id: str) -> Dict[str, Any]:
        """
        Loads the chunks from SQLite for the given source, computes embeddings for
        all chunks, and saves them to a NumPy binary file for cached storage.
        """
        workspace_dir = settings.workspaces_dir / workspace_id
        if not workspace_dir.exists():
            logger.warning(f"Workspace directory {workspace_dir} does not exist. Aborting embedding generation.")
            return {
                "source_id": source_id,
                "chunks_count": 0,
                "embedding_dim": 0,
                "cached": False
            }
        
        # Ensure directories exist
        embeddings_dir = workspace_dir / "embeddings"
        embeddings_dir.mkdir(parents=True, exist_ok=True)
        npy_file = embeddings_dir / f"{source_id}.npy"

        # Check if embeddings are already cached on disk (incremental indexing)
        if npy_file.exists():
            logger.info(f"Embeddings cache hit for source {source_id}. Skipping generation.")
            # Load from cache to verify shape and return stats
            cached_vectors = np.load(npy_file)
            return {
                "source_id": source_id,
                "chunks_count": len(cached_vectors),
                "embedding_dim": cached_vectors.shape[1],
                "cached": True
            }

        # Load text chunks from SQLite database
        from app.core.database import get_child_chunks
        try:
            chunks = get_child_chunks(workspace_id, source_id)
        except Exception as e:
            logger.error(f"Failed to load child chunks from SQLite for source {source_id}: {e}")
            chunks = []

        if not chunks:
            logger.info(f"No chunks found for source {source_id}. Skipping embeddings.")
            return {
                "source_id": source_id,
                "chunks_count": 0,
                "embedding_dim": 0,
                "cached": False
            }

        texts = [chunk["text"] for chunk in chunks]
        
        # Get singleton model
        model = get_embedding_model()
        if model is None:
            logger.error(
                "[Embeddings] Embedding model is not available. "
                "Run the Kivo setup script to download and build the ONNX model first."
            )
            return {
                "source_id": source_id,
                "chunks_count": 0,
                "embedding_dim": 0,
                "cached": False,
                "error": "Embedding model not available. Run setup to install."
            }

        logger.info(f"Encoding {len(texts)} chunks for source {source_id}...")
        
        # Generate normalized embeddings (so Inner Product matches Cosine Similarity in FAISS)
        embeddings = model.encode(
            texts,
            batch_size=32,   # Increased from 16 → 32 for better CPU throughput
            show_progress_bar=False,
            normalize_embeddings=True
        )
        
        # Save as float32 NumPy array
        vectors = np.array(embeddings, dtype=np.float32)
        np.save(npy_file, vectors)

        logger.info(f"Saved {len(vectors)} vectors of shape {vectors.shape} to {npy_file}")

        return {
            "source_id": source_id,
            "chunks_count": len(vectors),
            "embedding_dim": vectors.shape[1],
            "cached": False
        }
