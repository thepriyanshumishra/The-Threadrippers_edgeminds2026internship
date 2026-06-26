# backend/scripts/run_benchmark.py
import os
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["VECLIB_MAXIMUM_THREADS"] = "1"
os.environ["NUMEXPR_NUM_THREADS"] = "1"
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import sys
import json
import time
import shutil
import logging
import argparse
from pathlib import Path
import numpy as np
import requests

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(name)s | %(message)s")
logger = logging.getLogger("kivo.benchmark")

# Set sys.path to backend directory so we can import app
sys.path.insert(0, str(Path(__file__).parent.parent.absolute()))

import torch
import faiss

from app.core.config import settings
from app.core.processors.text import TextProcessor
from app.core.processors.embeddings import EmbeddingProcessor, get_embedding_model
from app.core.processors.vector_db import VectorDBProcessor
from app.core.retriever import retrieve_and_generate

# Sample Text Paragraphs (20 paragraphs)
SAMPLE_TEXT_PARAGRAPHS = [
    "Artificial Intelligence (AI) is one of the most transformative technologies developed by humanity. Although modern AI systems have become widely popular only in recent years, the foundations of the field were established decades ago. The concept of machines performing intelligent tasks can be traced back to ancient myths and mechanical inventions, but the scientific study of AI began in the mid-20th century.",
    "In 1950, British mathematician and computer scientist Alan Turing published a paper titled Computing Machinery and Intelligence. In this work, he proposed what later became known as the Turing Test, a method for evaluating whether a machine could exhibit behavior indistinguishable from that of a human. Turing's ideas significantly influenced future AI research.",
    "The term Artificial Intelligence was officially coined in 1956 during the Dartmouth Summer Research Project on Artificial Intelligence. Researchers believed that human intelligence could be precisely described and simulated by machines. Early optimism led many scientists to predict rapid progress toward human-level intelligence.",
    "During the 1960s and 1970s, AI research focused heavily on symbolic reasoning systems. These systems relied on explicitly programmed rules to solve problems. Expert systems emerged as one of the most successful applications of symbolic AI. They were capable of making decisions in specialized domains such as medical diagnosis and industrial troubleshooting.",
    "However, progress was slower than expected. Computers lacked sufficient processing power, and many real-world problems proved too complex for rule-based approaches. This led to periods known as \"AI winters,\" during which funding and public interest declined significantly.",
    "The resurgence of AI began in the 1990s and accelerated in the 2000s due to three major factors: increased computational power, the availability of large datasets, and advances in machine learning algorithms. Unlike symbolic systems, machine learning models learn patterns directly from data rather than relying entirely on manually written rules.",
    "One notable milestone occurred in 1997 when IBM's Deep Blue defeated world chess champion Garry Kasparov. This event demonstrated the growing capabilities of computational systems in specialized tasks.",
    "The emergence of deep learning marked another turning point. Deep learning uses artificial neural networks inspired by the structure of the human brain. These networks contain multiple layers capable of learning hierarchical representations of data. Breakthroughs in image recognition, speech recognition, and natural language processing followed.",
    "In 2012, a deep neural network known as AlexNet achieved remarkable success in the ImageNet competition, significantly reducing image classification error rates. This achievement is often considered the beginning of the modern deep learning revolution.",
    "Natural Language Processing (NLP) experienced major advances with the introduction of transformer architectures. Transformers rely on self-attention mechanisms that allow models to process relationships between words more effectively than previous recurrent neural network approaches.",
    "The transformer architecture was introduced in 2017 through the paper Attention Is All You Need. This innovation enabled the development of increasingly powerful language models capable of generating coherent text, answering questions, translating languages, and assisting with software development.",
    "Large Language Models (LLMs) are trained on vast amounts of text data collected from books, articles, websites, and other sources. During training, models learn statistical relationships between words, phrases, and concepts. Although these models can generate highly convincing responses, they do not possess human consciousness or genuine understanding.",
    "Modern AI systems are now deployed across numerous industries. Healthcare organizations use AI for medical imaging analysis, drug discovery, and patient risk assessment. Financial institutions employ AI for fraud detection, algorithmic trading, and credit scoring. Manufacturing companies use predictive maintenance systems to reduce equipment downtime.",
    "Transportation has also been transformed by AI technologies. Autonomous vehicle research combines computer vision, sensor fusion, planning algorithms, and machine learning to navigate complex environments. While fully autonomous vehicles remain a challenging goal, substantial progress continues.",
    "Ethical considerations have become increasingly important as AI capabilities grow. Researchers and policymakers debate issues including algorithmic bias, privacy, accountability, transparency, intellectual property, labor displacement, and the societal impact of automation.",
    "Algorithmic bias can emerge when training data contains historical inequalities or lacks sufficient diversity. As a result, AI systems may produce unfair outcomes for certain groups. Addressing bias requires careful dataset design, testing procedures, and ongoing monitoring.",
    "Privacy concerns arise because many AI systems rely on large amounts of user data. Organizations must balance innovation with responsible data governance practices. Regulations in various countries seek to establish standards for data protection and AI deployment.",
    "Another significant concern involves misinformation. Generative AI systems can create realistic text, images, audio, and videos. While these capabilities offer many beneficial applications, they also create opportunities for deception, fraud, and manipulation.",
    "The future of AI remains uncertain. Some experts predict the development of Artificial General Intelligence (AGI), a hypothetical system capable of performing any intellectual task that a human can perform. Others argue that current approaches may face fundamental limitations that require entirely new breakthroughs.",
    "Regardless of the ultimate trajectory, AI is likely to remain one of the most influential technologies of the 21st century. Its impact will depend not only on technical innovation but also on governance, ethics, education, and society's collective choices regarding how these systems are developed and used."
]

SAMPLE_TEXT = "\n\n".join(SAMPLE_TEXT_PARAGRAPHS)

def get_overlapping_paragraphs(chunk_text):
    overlapping = []
    for idx, p in enumerate(SAMPLE_TEXT_PARAGRAPHS):
        p_clean = p.strip()
        test_len = min(60, len(p_clean))
        if test_len > 10 and p_clean[:test_len] in chunk_text:
            overlapping.append(idx)
        elif p_clean in chunk_text or chunk_text in p_clean:
            overlapping.append(idx)
    return list(set(overlapping))

def evaluate_generation_correctness(question: str, expected: str, generated: str) -> dict:
    refusal_phrases = ["cannot answer", "not mention", "no mention", "not provide", "does not explain", "do not possess", "based on the provided context"]
    is_obvious_refusal = any(phrase in generated.lower() for phrase in refusal_phrases) or generated.lower().startswith("error:") or generated.lower().startswith("error calling")
    
    if is_obvious_refusal:
        return {
            "classification": "INCORRECT",
            "reason": "Direct refusal or system error detected in response."
        }
        
    # Fast-path substring matching to bypass flaky 1.5B LLM grading for direct matches
    def clean_text(t: str) -> str:
        import re
        t = t.lower()
        t = re.sub(r'\[[^\]]+\]', '', t) # Remove citations like [1] or [source_id_p0]
        t = re.sub(r"\'s\b", "", t)       # Strip possessive 's
        t = re.sub(r'[^\w\s]', '', t)     # Remove punctuation
        return " ".join(t.split())

    clean_exp = clean_text(expected)
    clean_gen = clean_text(generated)

    if clean_exp == clean_gen:
        return {
            "classification": "EXACT_MATCH",
            "reason": "The normalized generated answer matches the expected answer exactly."
        }
    if clean_exp in clean_gen:
        return {
            "classification": "SUBSTANTIALLY_CORRECT",
            "reason": "The expected answer is a substring of the generated answer."
        }
        
    def robust_json_parse(text: str) -> dict:
        import re
        text = text.strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Regex patterns for extraction when standard JSON parsing fails
        p1 = r'"classification"\s*:\s*"(?P<classification>[^"]+)"\s*,\s*"reason"\s*:\s*"(?P<reason>.*)"\s*\}'
        m1 = re.search(p1, text, re.DOTALL | re.IGNORECASE)
        if m1:
            return {
                "classification": m1.group("classification").strip(),
                "reason": m1.group("reason").strip()
            }

        p2 = r'"reason"\s*:\s*"(?P<reason>.*)"\s*,\s*"classification"\s*:\s*"(?P<classification>[^"]+)"\s*\}'
        m2 = re.search(p2, text, re.DOTALL | re.IGNORECASE)
        if m2:
            return {
                "classification": m2.group("classification").strip(),
                "reason": m2.group("reason").strip()
            }

        class_match = re.search(r'"classification"\s*:\s*"([^"]+)"', text, re.IGNORECASE)
        classification = class_match.group(1).strip() if class_match else "INCORRECT"

        reason_match = re.search(r'"reason"\s*:\s*"(.*)"', text, re.DOTALL | re.IGNORECASE)
        if reason_match:
            reason = reason_match.group(1).strip()
            if reason.endswith('}'):
                reason = reason[:-1].strip()
            if reason.endswith('"'):
                reason = reason[:-1].strip()
        else:
            reason = "No reason provided by evaluator."

        return {
            "classification": classification,
            "reason": reason
        }

    prompt = f"""You are a grading assistant. Compare the student's Generated Answer against the Expected Answer (Ground Truth) for the given Question.

Question: {question}
Expected Answer: {expected}
Generated Answer: {generated}

Grading Guidelines:
- If the Generated Answer contains the correct key entities (e.g., names, dates, numbers, concepts) and answers the question correctly, classify it as SUBSTANTIALLY_CORRECT.
- Be lenient on extra context, extra sentences, or minor phrasing differences. As long as the correct answer is present in the text, it is SUBSTANTIALLY_CORRECT.
- Only classify as INCORRECT if the generated answer is factually wrong, directly contradicts the expected answer, or fails to answer the question.

Classify the correctness of the Generated Answer into exactly one of these categories:
- EXACT_MATCH: The generated answer is word-for-word identical (ignoring minor punctuation/spacing).
- SUBSTANTIALLY_CORRECT: The generated answer contains all key facts/information from the expected answer, even with different phrasing or extra context.
- PARTIAL: The generated answer contains some correct facts but misses others.
- INCORRECT: The generated answer is wrong, contradicts the truth, or is a refusal.

Respond ONLY with a JSON object in this format:
{{
  "classification": "EXACT_MATCH | SUBSTANTIALLY_CORRECT | PARTIAL | INCORRECT",
  "reason": "One sentence explanation of why it fits this category."
}}
"""
    url = f"{settings.ollama_base_url}/api/generate"
    payload = {
        "model": "qwen2.5:1.5b",
        "prompt": prompt,
        "format": "json",
        "stream": False,
        "options": {
            "temperature": 0.0
        }
    }
    
    try:
        response = requests.post(url, json=payload, timeout=30)
        if response.status_code == 200:
            result = response.json()
            resp_text = result.get("response", "").strip()
            data = robust_json_parse(resp_text)
            classification = data.get("classification", "INCORRECT").upper()
            reason = data.get("reason", "No reason provided by evaluator.")
            
            valid_cats = ["EXACT_MATCH", "SUBSTANTIALLY_CORRECT", "PARTIAL", "INCORRECT"]
            if classification not in valid_cats:
                for cat in valid_cats:
                    if cat in classification:
                        classification = cat
                        break
                else:
                    classification = "INCORRECT"
                    
            return {
                "classification": classification,
                "reason": reason
            }
        else:
            return {
                "classification": "INCORRECT",
                "reason": f"Evaluator failed with status code {response.status_code}."
            }
    except Exception as e:
        return {
            "classification": "INCORRECT",
            "reason": f"Evaluator error: {e}"
        }

def run_benchmark():
    parser = argparse.ArgumentParser(description="Kivo Sprint 11 Automated Benchmark Runner")
    parser.add_argument("--full-trace", action="store_true", help="Dump full text of retrieved chunks to traces.jsonl")
    args = parser.parse_args()

    workspace_id = "benchmark_eval_ws"
    source_id = "benchmark_source_id"
    
    workspace_dir = settings.workspaces_dir / workspace_id
    shutil.rmtree(workspace_dir, ignore_errors=True)
    workspace_dir.mkdir(parents=True, exist_ok=True)
    
    # Create sources directory
    sources_dir = workspace_dir / "sources"
    sources_dir.mkdir(parents=True, exist_ok=True)
    
    # Write the sample text file
    txt_file_path = sources_dir / "evolution_of_ai.txt"
    with open(txt_file_path, "w", encoding="utf-8") as f:
        f.write(SAMPLE_TEXT)
        
    logger.info(f"Saved sample text to {txt_file_path}")
    
    # Create sources.json metadata
    sources_metadata = [
        {
            "name": "The Evolution of Artificial Intelligence",
            "type": "text",
            "id": source_id,
            "path": str(txt_file_path.relative_to(settings.storage_dir.parent)),
            "url": None,
            "added_at": "2026-06-17T00:00:00.000000Z",
            "size_bytes": len(SAMPLE_TEXT.encode("utf-8")),
            "status": "ready"
        }
    ]
    
    with open(workspace_dir / "sources.json", "w", encoding="utf-8") as f:
        json.dump(sources_metadata, f, indent=2)
    
    # 1. Run Chunking (TextProcessor - Parent-Child Splitter)
    logger.info("Step 1: Parent-Child boundary-aware chunking...")
    text_processor = TextProcessor(chunk_size=1000, chunk_overlap=200)
    text_processor.process(txt_file_path, workspace_id, source_id)
    
    # 2. Run Embedding Generation (EmbeddingProcessor)
    logger.info("Step 2: Generating GTE embeddings...")
    emb_processor = EmbeddingProcessor()
    emb_processor.process(workspace_id, source_id)
    
    # 3. Run Vector DB Index Compilation (VectorDBProcessor)
    logger.info("Step 3: Compiling FAISS index at 768-d...")
    vdb_processor = VectorDBProcessor(dimension=768)
    vdb_processor.process(workspace_id)
    
    # 4. Load benchmark dataset
    benchmark_file = Path(__file__).parent / "benchmark_v1.json"
    if not benchmark_file.exists():
        logger.error(f"Benchmark dataset not found at {benchmark_file}")
        sys.exit(1)
        
    with open(benchmark_file, "r", encoding="utf-8") as f:
        benchmark_data = json.load(f)
        
    dataset_version = benchmark_data.get("version", "unknown")
    questions = benchmark_data["questions"]
    
    eval_results = []
    
    hits_1 = 0
    hits_3 = 0
    hits_5 = 0
    mrr_sum = 0.0
    recall_sum = 0.0
    precision_sum = 0.0
    ndcg_sum = 0.0
    refusals = 0
    latency_sum = 0.0
    length_sum = 0.0
    
    refusal_phrases = ["cannot answer", "not mention", "no mention", "not provide", "does not explain", "do not possess", "based on the provided context"]
    
    logger.info("Step 4: Running question-by-question retrieval and generation...")
    
    for q_item in questions:
        q_num = q_item["number"]
        question = q_item["question"]
        gt_paragraphs = q_item["gt_paragraphs"]
        level = q_item["level"]
        
        logger.info(f"Evaluating Question {q_num}/{len(questions)} ({level}): {question}")
        
        # Run Kivo Sprint 11 retriever and generator
        res = retrieve_and_generate(
            workspace_id=workspace_id,
            question=question,
            model_name="qwen2.5:1.5b",
            max_parent_tokens=3500
        )
        
        retrieved_child_chunks = res["retrieved_child_chunks"]
        retrieved_parent_chunks = res["retrieved_parent_chunks"]
        answer = res["answer"]
        latency_ms = res["latency_ms"]
        routing_mode = res["routing_mode"]
        
        # Determine overlap paragraphs from child retrieval
        ret_paragraphs = []
        for r in retrieved_child_chunks:
            ret_paragraphs.extend(get_overlapping_paragraphs(r["text"]))
        ret_paragraphs = list(set(ret_paragraphs))
        
        # Hit@1 (on retrieved child chunks)
        top_1_paragraphs = get_overlapping_paragraphs(retrieved_child_chunks[0]["text"]) if retrieved_child_chunks else []
        is_hit_1 = any(p in gt_paragraphs for p in top_1_paragraphs)
        if is_hit_1:
            hits_1 += 1
            
        # Hit@3
        top_3_paragraphs = []
        for r in retrieved_child_chunks[:3]:
            top_3_paragraphs.extend(get_overlapping_paragraphs(r["text"]))
        is_hit_3 = any(p in gt_paragraphs for p in top_3_paragraphs)
        if is_hit_3:
            hits_3 += 1
            
        # Hit@5
        top_5_paragraphs = []
        for r in retrieved_child_chunks[:5]:
            top_5_paragraphs.extend(get_overlapping_paragraphs(r["text"]))
        is_hit_5 = any(p in gt_paragraphs for p in top_5_paragraphs)
        if is_hit_5:
            hits_5 += 1
            
        # MRR
        mrr_val = 0.0
        for rank, r in enumerate(retrieved_child_chunks, 1):
            r_paragraphs = get_overlapping_paragraphs(r["text"])
            if any(p in gt_paragraphs for p in r_paragraphs):
                mrr_val = 1.0 / rank
                break
        mrr_sum += mrr_val
        
        # Recall
        intersection = sum(1 for p in gt_paragraphs if p in ret_paragraphs)
        recall_val = intersection / len(gt_paragraphs) if gt_paragraphs else 1.0
        recall_sum += recall_val
        
        # Precision
        precision_val = intersection / len(ret_paragraphs) if ret_paragraphs else 0.0
        precision_sum += precision_val
        
        # NDCG
        dcg = 0.0
        idcg = 0.0
        for r_idx in range(min(len(retrieved_child_chunks), len(gt_paragraphs))):
            idcg += 1.0 / np.log2(r_idx + 2)
        
        for rank, r in enumerate(retrieved_child_chunks, 1):
            r_paragraphs = get_overlapping_paragraphs(r["text"])
            rel = 1.0 if any(p in gt_paragraphs for p in r_paragraphs) else 0.0
            dcg += rel / np.log2(rank + 1)
            
        ndcg_val = dcg / idcg if idcg > 0 else 1.0
        ndcg_sum += ndcg_val
        
        # Correctness evaluation
        plain_answer = res.get("plain_answer", answer)
        eval_res = evaluate_generation_correctness(question, q_item["expected_answer"], plain_answer)
        classification = eval_res["classification"]
        eval_reason = eval_res["reason"]
        
        # Refusal check
        is_refusal = any(phrase in answer.lower() for phrase in refusal_phrases) or answer.lower().startswith("error:") or answer.lower().startswith("error calling")
        if is_refusal:
            refusals += 1
            
        latency_sum += latency_ms
        length_sum += len(answer.split())
        
        # Save trace item
        trace_record = {
            "question": question,
            "child_ids": res["child_ids"],
            "parent_ids": res["parent_ids"],
            "routing_mode": routing_mode,
            "answer": answer,
            "latency_ms": latency_ms,
            "correctness": classification,
            "correctness_reason": eval_reason
        }
        if args.full_trace:
            trace_record["retrieved_child_chunks"] = retrieved_child_chunks
            trace_record["retrieved_parent_chunks"] = retrieved_parent_chunks
            
        eval_results.append({
            "number": q_num,
            "question": question,
            "level": level,
            "gt_paragraphs": gt_paragraphs,
            "expected_answer": q_item["expected_answer"],
            "answer": answer,
            "is_refusal": is_refusal,
            "is_hit_1": is_hit_1,
            "is_hit_3": is_hit_3,
            "mrr": mrr_val,
            "recall": recall_val,
            "precision": precision_val,
            "ndcg": ndcg_val,
            "latency_ms": latency_ms,
            "correctness": classification,
            "correctness_reason": eval_reason,
            "trace": trace_record
        })
        
    num_queries = len(questions)
    
    # Calculate final correctness metrics
    exact_matches = sum(1 for x in eval_results if x["correctness"] == "EXACT_MATCH")
    substantially_correct = sum(1 for x in eval_results if x["correctness"] == "SUBSTANTIALLY_CORRECT")
    partials = sum(1 for x in eval_results if x["correctness"] == "PARTIAL")
    incorrects = sum(1 for x in eval_results if x["correctness"] == "INCORRECT")
    gen_accuracy = (exact_matches + substantially_correct) / num_queries
    
    # Calculate final metrics
    final_metrics = {
        "dataset_version": dataset_version,
        "total_questions": num_queries,
        "hit_1": hits_1 / num_queries,
        "hit_3": hits_3 / num_queries,
        "hit_5": hits_5 / num_queries,
        "recall": recall_sum / num_queries,
        "precision": precision_sum / num_queries,
        "mrr": mrr_sum / num_queries,
        "ndcg": ndcg_sum / num_queries,
        "refusal_rate": refusals / num_queries,
        "generation_accuracy": gen_accuracy,
        "exact_match_rate": exact_matches / num_queries,
        "substantially_correct_rate": substantially_correct / num_queries,
        "partial_rate": partials / num_queries,
        "incorrect_rate": incorrects / num_queries,
        "avg_latency_ms": latency_sum / num_queries,
        "avg_length_words": length_sum / num_queries
    }
    
    # Create output directories
    scripts_results_dir = Path(__file__).parent / "results"
    scripts_results_dir.mkdir(parents=True, exist_ok=True)
    
    artifacts_dir = Path("/Users/thedarkpcm/.gemini/antigravity/brain/c5dc8fba-7b42-49be-9c39-1e8e2ed4bf2b")
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    
    # Save metrics.json
    for path in [scripts_results_dir / "metrics.json", artifacts_dir / "metrics.json"]:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(final_metrics, f, indent=2)
            
    # Save traces.jsonl
    for path in [scripts_results_dir / "traces.jsonl", artifacts_dir / "traces.jsonl"]:
        with open(path, "w", encoding="utf-8") as f:
            for item in eval_results:
                f.write(json.dumps(item["trace"]) + "\n")
                
    # Build benchmark_report.md
    report_lines = [
        f"# Kivo Sprint 11 Benchmark Report",
        f"",
        f"**Dataset Version**: `{dataset_version}`  ",
        f"**Date**: {time.strftime('%Y-%m-%d %H:%M:%S')}  ",
        f"**Routing Mode**: Intent-Based (STANDARD_QA / META_RETRIEVAL)  ",
        f"**Context Strategy**: Parent-Child Retrieval (Dynamic Context Reconstruction)  ",
        f"**Context Budget**: `MAX_PARENT_CONTEXT_TOKENS = 3500`  ",
        f"**Model**: `qwen2.5:1.5b` (Ollama, temperature=0.0)  ",
        f"",
        f"## 📊 Executive Performance Summary",
        f"",
        f"| Metric | Value | Target (Sprint 11) | Sprint 10 Baseline | Delta vs. Baseline |",
        f"| :--- | :---: | :---: | :---: | :---: |",
        f"| **Hit@1** | {final_metrics['hit_1']:.2%} | - | 78.33% | {final_metrics['hit_1'] - 0.7833:+.2%} |",
        f"| **Hit@3** | {final_metrics['hit_3']:.2%} | - | 96.67% | {final_metrics['hit_3'] - 0.9667:+.2%} |",
        f"| **Hit@5** | {final_metrics['hit_5']:.2%} | - | 96.67% | {final_metrics['hit_5'] - 0.9667:+.2%} |",
        f"| **MRR** | {final_metrics['mrr']:.4f} | - | 0.8722 | {final_metrics['mrr'] - 0.8722:+.4f} |",
        f"| **Recall** | {final_metrics['recall']:.2%} | - | 83.38% | {final_metrics['recall'] - 0.8338:+.2%} |",
        f"| **Precision** | {final_metrics['precision']:.2%} | - | 20.63% | {final_metrics['precision'] - 0.2063:+.2%} |",
        f"| **NDCG** | {final_metrics['ndcg']:.4f} | - | 0.8758 | {final_metrics['ndcg'] - 0.8758:+.4f} |",
        f"| **Generation Accuracy** | {final_metrics['generation_accuracy']:.2%} | - | - | - |",
        f"| **Exact Match Rate** | {final_metrics['exact_match_rate']:.2%} | - | - | - |",
        f"| **Substantially Correct** | {final_metrics['substantially_correct_rate']:.2%} | - | - | - |",
        f"| **Partial Correctness** | {final_metrics['partial_rate']:.2%} | - | - | - |",
        f"| **Incorrect/Refusal Rate** | {final_metrics['incorrect_rate']:.2%} | - | - | - |",
        f"| **Refusal Rate** | {final_metrics['refusal_rate']:.2%} | **< 10.00%** | 21.67% | {final_metrics['refusal_rate'] - 0.2167:+.2%} |",
        f"| **Avg Latency** | {final_metrics['avg_latency_ms'] / 1000:.2f}s | - | 11.24s | {final_metrics['avg_latency_ms'] / 1000 - 11.24:+.2f}s |",
        f"| **Avg Word Count** | {final_metrics['avg_length_words']:.1f} words | - | 111.7 words | {final_metrics['avg_length_words'] - 111.7:+.1f} |",
        f"",
        f"## 🧩 Performance by Difficulty Level",
        f""
    ]
    
    # Categorize results by level
    levels_map = {}
    for item in eval_results:
        lvl = item["level"]
        if lvl not in levels_map:
            levels_map[lvl] = []
        levels_map[lvl].append(item)
        
    report_lines.append("| Difficulty Level | Questions | Hit@3 | Refusal Rate | Avg Latency |")
    report_lines.append("| :--- | :---: | :---: | :---: | :---: |")
    for lvl, items in levels_map.items():
        lvl_hits = sum(1 for x in items if x["is_hit_3"])
        lvl_refusals = sum(1 for x in items if x["is_refusal"])
        lvl_latency = sum(x["latency_ms"] for x in items) / len(items)
        report_lines.append(f"| {lvl} | {len(items)} | {lvl_hits / len(items):.2%} | {lvl_refusals / len(items):.2%} | {lvl_latency / 1000:.2f}s |")
        
    report_lines.append("")
    report_lines.append("## 📝 Detailed Question-by-Question Trace Audit")
    report_lines.append("")
    
    for item in eval_results:
        report_lines.append(f"### Question {item['number']}")
        report_lines.append(f"**Question**: {item['question']}")
        report_lines.append(f"**Level**: {item['level']}")
        report_lines.append(f"**Routing Mode**: `{item['trace']['routing_mode']}`")
        report_lines.append(f"**Recall**: {item['recall']:.2%} | **Hit@3**: {'✅ Yes' if item['is_hit_3'] else '❌ No'}")
        report_lines.append(f"**Refused**: {'⚠️ Yes' if item['is_refusal'] else '✅ No'}")
        report_lines.append(f"**Correctness Category**: `{item['correctness']}`")
        report_lines.append(f"**Evaluator Reason**: *{item['correctness_reason']}*")
        report_lines.append("")
        report_lines.append("#### Expected Answer:")
        report_lines.append(f"> {item['expected_answer']}")
        report_lines.append("")
        report_lines.append("#### Generated Answer:")
        report_lines.append("```text")
        report_lines.append(item["answer"])
        report_lines.append("```")
        report_lines.append("")
        report_lines.append("---")
        report_lines.append("")
        
    # Write report
    report_str = "\n".join(report_lines)
    for path in [scripts_results_dir / "benchmark_report.md", artifacts_dir / "benchmark_report.md"]:
        with open(path, "w", encoding="utf-8") as f:
            f.write(report_str)
            
    logger.info("Step 5: Cleaning up temporary benchmark workspace...")
    shutil.rmtree(workspace_dir, ignore_errors=True)
    logger.info("Cleanup complete.")
    
    print("SUCCESS: Automated benchmark run finished successfully.")
    print(f"Metrics saved to metrics.json")
    print(f"Report generated at benchmark_report.md")

if __name__ == "__main__":
    run_benchmark()
