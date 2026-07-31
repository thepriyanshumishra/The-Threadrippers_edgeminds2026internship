#!/usr/bin/env python3
"""
Kivo Workspace — Integration Test Suite (Phase 9)
Run with backend live: python tests/test_integration.py
Tests: health, CRUD, input validation, all 3 chat modes, RAG, security, streaming headers.
"""

import httpx
import json
import sys
import time
import io
import os

BASE = os.getenv("KIVO_URL", "http://localhost:8000")
STREAM_TIMEOUT = 120
PASS = "\033[92m✅ PASS\033[0m"
FAIL = "\033[91m❌ FAIL\033[0m"
results = []

def check(name: str, passed: bool, detail: str = ""):
    icon = PASS if passed else FAIL
    print(f"  {icon}  {name}" + (f" — {detail}" if detail else ""))
    results.append((name, passed))

def section(title: str):
    print(f"\n{'='*55}\n  {title}\n{'='*55}")

def create_workspace(name="Test Workspace"):
    r = httpx.post(f"{BASE}/workspaces", json={"name": name}, timeout=10)
    return r.json()["id"] if r.status_code == 200 else None

def delete_workspace(wid: str):
    httpx.delete(f"{BASE}/workspaces/{wid}", timeout=10)

def stream_chat(wid: str, query: str, mode: str = "default"):
    full_text, citations, got_heartbeat = "", [], False
    with httpx.stream("POST", f"{BASE}/workspaces/{wid}/chat/stream",
                      json={"query": query, "mode": mode, "model": "qwen2.5:1.5b"},
                      timeout=STREAM_TIMEOUT) as r:
        for line in r.iter_lines():
            if line.startswith(": heartbeat"):
                got_heartbeat = True
            elif line.startswith("data:"):
                data = line[5:].strip()
                if not data or data == "[DONE]":
                    continue
                try:
                    obj = json.loads(data)
                    if "token" in obj:
                        full_text += obj["token"]
                    if "citations" in obj:
                        citations = obj["citations"]
                except json.JSONDecodeError:
                    pass
    return full_text, citations, got_heartbeat

# ── 1. Health ─────────────────────────────────────────────
section("1. Health Check")
try:
    r = httpx.get(f"{BASE}/health", timeout=5)
    check("Backend reachable", r.status_code == 200)
    check("Health returns ok", r.json().get("status") == "ok")
except Exception as e:
    check("Backend reachable", False, str(e))
    print("\n  ⚠️  Start backend with ./start.sh then re-run.")
    sys.exit(1)

# ── 2. Workspace CRUD ──────────────────────────────────────
section("2. Workspace CRUD")
wid = create_workspace("Integration Test WS")
check("Create workspace", wid is not None)

if wid:
    ids = [w["id"] for w in httpx.get(f"{BASE}/workspaces", timeout=10).json()]
    check("Workspace in list", wid in ids)
    check("Get workspace", httpx.get(f"{BASE}/workspaces/{wid}", timeout=10).status_code == 200)
    check("Rename workspace", httpx.patch(f"{BASE}/workspaces/{wid}", json={"name": "Renamed"}, timeout=10).status_code == 200)

    r = httpx.post(f"{BASE}/workspaces", json={"name": "../../../etc/passwd"}, timeout=10)
    if r.status_code == 200:
        evil_name = r.json().get("name", "")
        check("Path traversal sanitized", ".." not in evil_name, f"got: {evil_name!r}")
        delete_workspace(r.json().get("id", ""))
    else:
        check("Path traversal rejected", r.status_code in (400, 422))

# ── 3. Input Validation ────────────────────────────────────
section("3. Input Validation")
if wid:
    r = httpx.post(f"{BASE}/workspaces/{wid}/chat/stream",
                   json={"query": "", "mode": "default", "model": "qwen2.5:1.5b"}, timeout=10)
    check("Empty query → 400", r.status_code == 400, f"HTTP {r.status_code}")

    r = httpx.post(f"{BASE}/workspaces/{wid}/chat/stream",
                   json={"query": "a"*8001, "mode": "default", "model": "qwen2.5:1.5b"}, timeout=10)
    check("8001-char query → 400", r.status_code == 400, f"HTTP {r.status_code}")

    r = httpx.post(f"{BASE}/workspaces/{wid}/chat/stream",
                   json={"query": "hello", "mode": "INVALID", "model": "qwen2.5:1.5b"}, timeout=10)
    check("Invalid mode → 422", r.status_code == 422, f"HTTP {r.status_code}")

    r = httpx.post(f"{BASE}/workspaces/{wid}/chat/stream",
                   json={"query": "नमस्ते 🙏 مرحبا", "mode": "explore", "model": "qwen2.5:1.5b"}, timeout=10)
    check("Hindi/Arabic/emoji accepted → 200", r.status_code == 200, f"HTTP {r.status_code}")

# ── 4. Explore Mode (no RAG) ───────────────────────────────
section("4. Explore Mode")
if wid:
    try:
        text, cit, heartbeat = stream_chat(wid, "What is the capital of France?", "explore")
        check("Explore: response streamed", len(text) > 10, f"{len(text)} chars")
        check("Explore: no citations", len(cit) == 0, f"{len(cit)} citations")
        check("SSE heartbeat received", heartbeat)
    except Exception as e:
        check("Explore mode", False, str(e))

# ── 5. Strict Mode — Empty Workspace ──────────────────────
section("5. Strict Mode — Empty Workspace")
if wid:
    try:
        text, _, _ = stream_chat(wid, "What does the document say?", "strict")
        refusal = any(w in text.lower() for w in ["don't have","cannot","no document","no sources","not find","unable","not available"])
        check("Strict empty WS: polite refusal", refusal, text[:80])
    except Exception as e:
        check("Strict mode empty WS", False, str(e))

# ── 6. Default Mode — Empty Workspace ─────────────────────
section("6. Default Mode — Empty Workspace")
if wid:
    try:
        text, _, _ = stream_chat(wid, "Tell me about photosynthesis", "default")
        check("Default empty WS: fallback response", len(text) > 10, f"{len(text)} chars")
    except Exception as e:
        check("Default mode empty WS", False, str(e))

# ── 7. Text Source + RAG ───────────────────────────────────
section("7. Text Source + Strict/Default RAG")
src_id = None
if wid:
    r = httpx.post(f"{BASE}/workspaces/{wid}/sources/text",
                   json={"name": "test-doc", "content": "The Kivo project was founded in 2026. Its main feature is offline RAG."},
                   timeout=15)
    check("Text source created", r.status_code == 200)
    if r.status_code == 200:
        src_id = r.json().get("id")

    if src_id:
        for _ in range(25):
            time.sleep(1)
            status = httpx.get(f"{BASE}/workspaces/{wid}/sources/{src_id}", timeout=10).json().get("status","?")
            if status == "ready":
                break
        check("Source processed → ready", status == "ready", f"status={status}")

        if status == "ready":
            text, cit, _ = stream_chat(wid, "When was Kivo founded?", "strict")
            check("Strict: answer in doc found", "2026" in text, text[:100])
            check("Strict: citations returned", len(cit) > 0, f"{len(cit)} citations")

            text2, _, _ = stream_chat(wid, "What is the population of Tokyo?", "strict")
            refusal = any(w in text2.lower() for w in ["don't have","cannot","no information","not find","unable","not available"])
            check("Strict: OOD question → refusal", refusal, text2[:100])

            text3, _, _ = stream_chat(wid, "What is offline RAG and how does Kivo use it?", "default")
            check("Default: hybrid answer received", len(text3) > 20, f"{len(text3)} chars")

# ── 8. Security — Path Traversal Upload ───────────────────
section("8. Security — File Upload Path Traversal")
if wid:
    files = {"file": ("../../../../etc/passwd", io.BytesIO(b"dummy"), "text/plain")}
    r = httpx.post(f"{BASE}/workspaces/{wid}/sources/upload", files=files, timeout=15)
    if r.status_code in (200, 201):
        safe = r.json().get("name", "")
        check("Evil filename sanitized", ".." not in safe, f"got: {safe!r}")
    else:
        check("Evil filename rejected", r.status_code in (400, 413, 422), f"HTTP {r.status_code}")

# ── 9. Streaming Headers ───────────────────────────────────
section("9. Streaming Headers")
if wid:
    with httpx.stream("POST", f"{BASE}/workspaces/{wid}/chat/stream",
                      json={"query": "hi", "mode": "explore", "model": "qwen2.5:1.5b"},
                      timeout=STREAM_TIMEOUT) as r:
        check("X-Accel-Buffering: no",
              r.headers.get("x-accel-buffering","").lower() == "no",
              repr(r.headers.get("x-accel-buffering","MISSING")))
        check("Content-Type: text/event-stream",
              "text/event-stream" in r.headers.get("content-type",""),
              r.headers.get("content-type",""))
        for _ in r.iter_lines():
            pass

# ── 10. Cleanup ────────────────────────────────────────────
section("10. Cleanup")
if wid:
    check("Delete workspace", httpx.delete(f"{BASE}/workspaces/{wid}", timeout=10).status_code == 200)

# ── Summary ────────────────────────────────────────────────
section("RESULTS")
total, passed = len(results), sum(1 for _, ok in results if ok)
print(f"\n  Passed : {passed}/{total}")
if passed < total:
    print(f"  Failed : {total-passed}/{total}")
    for name, ok in results:
        if not ok:
            print(f"    ❌ {name}")
    sys.exit(1)
else:
    print(f"\n  🎉 All {total} integration tests passed!")
    sys.exit(0)
