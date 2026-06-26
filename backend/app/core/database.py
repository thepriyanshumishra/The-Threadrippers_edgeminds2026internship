# app/core/database.py
import sqlite3
import json
import logging
from pathlib import Path
from typing import Dict, Any, List, Tuple

from app.core.config import settings

logger = logging.getLogger("kivo.core.database")

def get_db_connection(workspace_id: str) -> sqlite3.Connection:
    workspace_dir = settings.workspaces_dir / workspace_id
    
    # If the workspace directory and metadata.json both don't exist,
    # the workspace has been deleted. Do not recreate it!
    metadata_file = workspace_dir / "metadata.json"
    if not workspace_dir.exists() and not metadata_file.exists():
        raise FileNotFoundError(f"Workspace {workspace_id} has been deleted.")
        
    workspace_dir.mkdir(parents=True, exist_ok=True)
    db_path = workspace_dir / "metadata.db"
    
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn

def init_db(workspace_id: str):
    """Initializes the database schema and indexes."""
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS parent_chunks (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        parent_index INTEGER NOT NULL,
        text TEXT NOT NULL
    );
    """)
    
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS child_chunks (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        child_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        parent_id TEXT,
        metadata_json TEXT,
        global_vector_index INTEGER,
        FOREIGN KEY (parent_id) REFERENCES parent_chunks (id) ON DELETE CASCADE
    );
    """)
    
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_child_global_vector_index ON child_chunks (global_vector_index);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_child_source_id ON child_chunks (source_id);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_parent_source_id ON parent_chunks (source_id);")
    
    conn.commit()
    conn.close()

def save_chunks_to_db(workspace_id: str, source_id: str, parent_texts: List[str], child_chunks: List[Dict[str, Any]]):
    """
    Cleans out old chunks for a source and inserts the new parent and child chunks.
    """
    init_db(workspace_id)
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    
    try:
        # Delete existing chunks for this source to support overwriting/re-processing
        cursor.execute("DELETE FROM parent_chunks WHERE source_id = ?", (source_id,))
        cursor.execute("DELETE FROM child_chunks WHERE source_id = ?", (source_id,))
        
        # Insert parents
        parent_data = []
        for idx, text in enumerate(parent_texts):
            p_id = f"{source_id}_p{idx}"
            parent_data.append((p_id, source_id, idx, text))
            
        cursor.executemany(
            "INSERT INTO parent_chunks (id, source_id, parent_index, text) VALUES (?, ?, ?, ?)",
            parent_data
        )
        
        # Insert children
        child_data = []
        for c in child_chunks:
            c_idx = c["index"]
            c_id = f"{source_id}_c{c_idx}"
            c_text = c["text"]
            meta = c.get("metadata", {})
            p_idx = meta.get("parent_id")
            p_id = f"{source_id}_p{p_idx}" if p_idx is not None else None
            
            meta_serialized = json.dumps(meta)
            child_data.append((c_id, source_id, c_idx, c_text, p_id, meta_serialized, None))
            
        cursor.executemany(
            "INSERT INTO child_chunks (id, source_id, child_index, text, parent_id, metadata_json, global_vector_index) VALUES (?, ?, ?, ?, ?, ?, ?)",
            child_data
        )
        
        conn.commit()
        logger.info(f"Saved {len(parent_texts)} parents and {len(child_chunks)} children to SQLite for source {source_id}.")
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to save chunks to SQLite for source {source_id}: {e}")
        raise e
    finally:
        conn.close()

def get_child_chunks(workspace_id: str, source_id: str) -> List[Dict[str, Any]]:
    """Retrieves all child chunks for a given source."""
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    
    cursor.execute(
        "SELECT child_index, text, parent_id, metadata_json FROM child_chunks WHERE source_id = ? ORDER BY child_index",
        (source_id,)
    )
    rows = cursor.fetchall()
    conn.close()
    
    chunks = []
    for r in rows:
        meta = json.loads(r["metadata_json"]) if r["metadata_json"] else {}
        chunks.append({
            "index": r["child_index"],
            "text": r["text"],
            "metadata": meta
        })
    return chunks

def update_global_vector_indices(workspace_id: str, mappings: List[Tuple[str, int]]):
    """
    Updates global vector indices for the indexed child chunks.
    mappings: list of tuples (child_chunk_id, global_vector_index)
    """
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    try:
        # Reset all global vector indices first
        cursor.execute("UPDATE child_chunks SET global_vector_index = NULL")
        
        cursor.executemany(
            "UPDATE child_chunks SET global_vector_index = ? WHERE id = ?",
            [(idx, cid) for cid, idx in mappings]
        )
        conn.commit()
        logger.info(f"Updated global vector indices for {len(mappings)} chunks in SQLite.")
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to update global vector indices: {e}")
        raise e
    finally:
        conn.close()

def get_child_chunks_by_global_indices(workspace_id: str, indices: List[int]) -> List[Dict[str, Any]]:
    """Retrieves child chunks corresponding to list of global vector indices, keeping database open once."""
    if not indices:
        return []
        
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    
    placeholders = ",".join("?" for _ in indices)
    query = f"""
        SELECT id, source_id, child_index, text, parent_id, metadata_json, global_vector_index
        FROM child_chunks
        WHERE global_vector_index IN ({placeholders})
    """
    
    cursor.execute(query, indices)
    rows = cursor.fetchall()
    conn.close()
    
    results = []
    for r in rows:
        results.append({
            "id": r["id"],
            "source_id": r["source_id"],
            "child_index": r["child_index"],
            "text": r["text"],
            "parent_id": r["parent_id"],
            "metadata": json.loads(r["metadata_json"]) if r["metadata_json"] else {},
            "global_vector_index": r["global_vector_index"]
        })
    return results

def get_parent_chunks_by_ids(workspace_id: str, parent_ids: List[str]) -> List[Dict[str, Any]]:
    """Retrieves parent chunks by their composite IDs."""
    if not parent_ids:
        return []
        
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    
    placeholders = ",".join("?" for _ in parent_ids)
    query = f"""
        SELECT id, source_id, parent_index, text
        FROM parent_chunks
        WHERE id IN ({placeholders})
    """
    
    cursor.execute(query, parent_ids)
    rows = cursor.fetchall()
    conn.close()
    
    results = []
    for r in rows:
        results.append({
            "id": r["id"],
            "source_id": r["source_id"],
            "parent_index": r["parent_index"],
            "text": r["text"]
        })
    return results

def delete_source_chunks(workspace_id: str, source_id: str):
    """Deletes all parent and child chunks associated with a source."""
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM parent_chunks WHERE source_id = ?", (source_id,))
        cursor.execute("DELETE FROM child_chunks WHERE source_id = ?", (source_id,))
        conn.commit()
        logger.info(f"Deleted SQLite chunks for source {source_id}.")
    except Exception as e:
        conn.rollback()
        logger.error(f"Failed to delete SQLite chunks for source {source_id}: {e}")
    finally:
        conn.close()

def get_all_parent_chunks_ordered(workspace_id: str) -> List[Dict[str, Any]]:
    """Retrieves all parent chunks in their natural reading order (by source_id, then parent_index)."""
    conn = get_db_connection(workspace_id)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, source_id, parent_index, text
        FROM parent_chunks
        ORDER BY source_id, parent_index
    """)
    rows = cursor.fetchall()
    conn.close()
    
    results = []
    for r in rows:
        results.append({
            "id": r["id"],
            "source_id": r["source_id"],
            "parent_index": r["parent_index"],
            "text": r["text"]
        })
    return results

