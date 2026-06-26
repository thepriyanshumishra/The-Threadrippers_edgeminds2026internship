# app/core/processors/vector_db.py
# Purpose: Local vector database index compilation pipeline.
# Responsibilities:
#   1. Compiles all computed chunk embeddings and texts for a workspace.
#   2. Indexes full 768-dimensional embeddings (no dimension truncation).
#   3. Normalizes vectors and builds a workspace-wide FAISS IndexFlatIP.
#   4. Persists the index (index.faiss) and mapping file (chunk_map.json) to disk.

try:
    import torch  # Prevent OpenMP/MKL conflict with faiss on macOS
except ImportError:
    pass
import json
import logging
from pathlib import Path
from typing import Dict, Any, List
import numpy as np
import faiss

from app.core.config import settings
from app.api.routes.sources import load_sources

logger = logging.getLogger("kivo.processors.vector_db")


class VectorDBProcessor:
    def __init__(self, dimension: int = 768):
        self.dimension = dimension

    def process(self, workspace_id: str) -> Dict[str, Any]:
        """
        Loads all chunks and embeddings for the workspace, normalizes them,
        builds/saves a FAISS index, and saves the matching chunk_map.json.
        """
        logger.info(f"Building FAISS Vector Index for workspace {workspace_id}...")
        workspace_dir = settings.workspaces_dir / workspace_id
        if not workspace_dir.exists():
            logger.warning(f"Workspace directory {workspace_dir} does not exist. Aborting FAISS index building.")
            return {"vectors_indexed": 0, "dimension": self.dimension}
        
        # Load all sources registered in sources.json
        sources = load_sources(workspace_id)
        if not sources:
            logger.warning(f"No sources registered for workspace {workspace_id}.")
            return {"vectors_indexed": 0, "dimension": self.dimension}

        all_vectors = []
        mappings = []
        global_idx = 0

        # Import database helpers
        from app.core.database import get_child_chunks, update_global_vector_indices

        for src in sources:
            # We only index sources that are ready/processed or currently being finalized
            if src.status not in ["ready", "processing"]:
                logger.info(f"Skipping source {src.id} (status: {src.status})")
                continue

            npy_file = workspace_dir / "embeddings" / f"{src.id}.npy"

            if not npy_file.exists():
                logger.warning(f"Missing embeddings for source {src.id}. Skipping.")
                continue

            try:
                # Load numpy vectors (shape: [num_chunks, 768])
                vectors = np.load(npy_file)
                
                # Load corresponding chunk texts from SQLite
                chunks = get_child_chunks(workspace_id, src.id)

                if len(vectors) != len(chunks):
                    logger.error(
                        f"Mismatch between vectors count ({len(vectors)}) and chunks count ({len(chunks)}) for source {src.id}."
                    )
                    continue

                # Ensure contiguous memory layout for FAISS
                vectors_contiguous = vectors.copy().astype(np.float32)
                
                # Normalize vectors to unit length so Inner Product matches Cosine Similarity
                faiss.normalize_L2(vectors_contiguous)

                all_vectors.append(vectors_contiguous)

                for chunk in chunks:
                    c_id = f"{src.id}_c{chunk['index']}"
                    mappings.append((c_id, global_idx))
                    global_idx += 1

            except Exception as e:
                logger.error(f"Failed to load/process vectors for source {src.id}: {e}")
                continue

        if not all_vectors:
            logger.warning("No vectors found to build FAISS index.")
            # Save empty files to avoid breaking retrieval
            self._save_empty_index(workspace_id, workspace_dir)
            return {"vectors_indexed": 0, "dimension": self.dimension}

        # Concatenate all lists of vectors
        vectors_np = np.vstack(all_vectors).astype(np.float32)
        total_vectors = len(vectors_np)

        # Initialize FAISS IndexFlatIP (Inner Product Index)
        # For L2 normalized vectors, Inner Product is mathematically identical to Cosine Similarity.
        index = faiss.IndexFlatIP(self.dimension)
        index.add(vectors_np)

        # Write index file to disk
        index_file = workspace_dir / "index.faiss"
        faiss.write_index(index, str(index_file))

        # Write chunk mapping to SQLite database
        update_global_vector_indices(workspace_id, mappings)

        logger.info(
            f"FAISS index built and saved successfully. "
            f"Indexed {total_vectors} chunks at {self.dimension} dimensions."
        )

        return {
            "vectors_indexed": total_vectors,
            "dimension": self.dimension
        }

    def _save_empty_index(self, workspace_id: str, workspace_dir: Path):
        """Helper to create empty placeholder vector DB files."""
        index = faiss.IndexFlatIP(self.dimension)
        faiss.write_index(index, str(workspace_dir / "index.faiss"))
        from app.core.database import update_global_vector_indices
        update_global_vector_indices(workspace_id, [])
