"""Chunk a Claude Code session jsonl into model-friendly pieces.

Lossless: preserves all message types except `file-history-snapshot`,
keeps tool_use args and full tool_result content, and splits oversized
single messages into marked parts so nothing is dropped.
"""
import argparse
import json
import os
import sys
from typing import Any


EXCLUDED_TYPES = {"file-history-snapshot"}


def _stringify_content(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for c in content:
            if not isinstance(c, dict):
                parts.append(str(c))
                continue
            ctype = c.get("type")
            if ctype == "text":
                parts.append(c.get("text", ""))
            elif ctype == "tool_use":
                name = c.get("name", "")
                args = c.get("input", {})
                parts.append(f"[tool_use: {name} {json.dumps(args, ensure_ascii=False)}]")
            elif ctype == "tool_result":
                inner = c.get("content", "")
                if isinstance(inner, list):
                    inner = "".join(
                        x.get("text", "") if isinstance(x, dict) else str(x)
                        for x in inner
                    )
                parts.append(f"[tool_result: {inner}]")
            else:
                parts.append(json.dumps(c, ensure_ascii=False))
        return "\n".join(parts)
    return json.dumps(content, ensure_ascii=False)


def _record_to_text(rec: dict) -> str:
    rtype = rec.get("type", "")
    msg = rec.get("message")
    if isinstance(msg, dict):
        role = msg.get("role", rtype)
        body = _stringify_content(msg.get("content", ""))
        return f"{role.upper()}: {body}"
    payload = {k: v for k, v in rec.items() if k not in ("type", "uuid", "parentUuid", "timestamp")}
    return f"{rtype.upper()}: {json.dumps(payload, ensure_ascii=False)}"


def split_large_messages(messages: list[dict], max_chars: int = 80_000) -> list[dict]:
    """Split any single message larger than max_chars into marked parts.

    Each part is `[LARGE MESSAGE k/N]\\n<body>` with len(part) <= max_chars.
    Concatenating the bodies in order recovers the original text exactly.
    """
    marker_overhead = 100  # safe headroom for "[LARGE MESSAGE 999/999]\n"
    body_max = max_chars - marker_overhead
    if body_max <= 0:
        raise ValueError("max_chars too small")
    out: list[dict] = []
    for msg in messages:
        text = msg["text"]
        if len(text) <= max_chars:
            out.append(msg)
            continue
        n = (len(text) + body_max - 1) // body_max
        for k in range(n):
            body = text[k * body_max : (k + 1) * body_max]
            out.append({
                "type": msg["type"],
                "text": f"[LARGE MESSAGE {k + 1}/{n}]\n{body}",
            })
    return out


def build_chunks(messages: list[dict], max_chars: int = 80_000, overlap: int = 0) -> list[list[dict]]:
    """Group messages into chunks of <= max_chars, never splitting a message.

    A single message larger than max_chars becomes its own (oversized) chunk;
    KR4 (split_large_message) is responsible for breaking such messages into
    marked parts before this function is called.
    """
    if not messages:
        return []
    chunks: list[list[dict]] = []
    current: list[dict] = []
    current_size = 0
    for msg in messages:
        msg_len = len(msg["text"])
        if current and current_size + msg_len > max_chars:
            chunks.append(current)
            if overlap > 0:
                tail = current[-overlap:]
                current = list(tail)
                current_size = sum(len(m["text"]) for m in current)
            else:
                current = []
                current_size = 0
        current.append(msg)
        current_size += msg_len
    if current:
        chunks.append(current)
    return chunks


def parse_messages(path: str) -> list[dict]:
    """Parse a session jsonl, returning a list of {type, text} dicts.

    Drops malformed lines and excluded types. Everything else is preserved
    as-is and stringified.
    """
    out = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(rec, dict):
                continue
            rtype = rec.get("type", "")
            if rtype in EXCLUDED_TYPES:
                continue
            text = _record_to_text(rec)
            out.append({"type": rtype, "text": text})
    return out


def chunk_session(path: str, max_chars: int = 80_000, overlap: int = 2) -> list[list[dict]]:
    """End-to-end: parse → split-large → build chunks."""
    msgs = parse_messages(path)
    msgs = split_large_messages(msgs, max_chars=max_chars)
    return build_chunks(msgs, max_chars=max_chars, overlap=overlap)


def _format_chunk(chunk: list[dict]) -> str:
    return "\n\n---\n\n".join(m["text"] for m in chunk)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Chunk a Claude Code session jsonl losslessly.")
    p.add_argument("jsonl", help="Path to session .jsonl file")
    p.add_argument("--out-dir", required=True, help="Directory to write chunk_NNN.txt files")
    p.add_argument("--max-chars", type=int, default=80_000)
    p.add_argument("--overlap", type=int, default=2)
    args = p.parse_args(argv)

    chunks = chunk_session(args.jsonl, max_chars=args.max_chars, overlap=args.overlap)
    os.makedirs(args.out_dir, exist_ok=True)
    for i, ch in enumerate(chunks, start=1):
        out_path = os.path.join(args.out_dir, f"chunk_{i:03d}.txt")
        with open(out_path, "w") as f:
            f.write(_format_chunk(ch))
    print(json.dumps({"chunks": len(chunks), "out_dir": args.out_dir}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
