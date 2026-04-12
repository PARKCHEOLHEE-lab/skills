"""Tests for chunk_and_extract."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from chunk_and_extract import build_chunks, parse_messages, split_large_messages


def write_jsonl(records):
    fd, path = tempfile.mkstemp(suffix=".jsonl")
    with os.fdopen(fd, "w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")
    return path


class TestParseMessages(unittest.TestCase):
    def test_excludes_file_history_snapshot(self):
        path = write_jsonl([
            {"type": "user", "message": {"role": "user", "content": "hello"}},
            {"type": "file-history-snapshot", "snapshot": {"trackedFileBackups": {"a.py": "x"}}},
            {"type": "assistant", "message": {"role": "assistant", "content": "hi"}},
        ])
        msgs = parse_messages(path)
        kinds = [m["type"] for m in msgs]
        self.assertNotIn("file-history-snapshot", kinds)
        self.assertEqual(kinds, ["user", "assistant"])

    def test_preserves_user_text(self):
        path = write_jsonl([
            {"type": "user", "message": {"role": "user", "content": "the answer is 42"}},
        ])
        msgs = parse_messages(path)
        self.assertEqual(len(msgs), 1)
        self.assertIn("the answer is 42", msgs[0]["text"])

    def test_preserves_tool_use_with_args(self):
        path = write_jsonl([
            {"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": "ls -la /tmp"}}
            ]}},
        ])
        msgs = parse_messages(path)
        self.assertEqual(len(msgs), 1)
        self.assertIn("Bash", msgs[0]["text"])
        self.assertIn("ls -la /tmp", msgs[0]["text"])

    def test_preserves_full_tool_result(self):
        long_text = "X" * 5000
        path = write_jsonl([
            {"type": "user", "message": {"role": "user", "content": [
                {"type": "tool_result", "content": [{"type": "text", "text": long_text}]}
            ]}},
        ])
        msgs = parse_messages(path)
        self.assertEqual(len(msgs), 1)
        self.assertIn(long_text, msgs[0]["text"])

    def test_preserves_other_types(self):
        path = write_jsonl([
            {"type": "system", "content": "system reminder"},
            {"type": "pr-link", "url": "https://github.com/x/y/pull/1"},
            {"type": "user", "message": {"role": "user", "content": "hi"}},
        ])
        msgs = parse_messages(path)
        kinds = [m["type"] for m in msgs]
        self.assertEqual(kinds, ["system", "pr-link", "user"])

    def test_skips_malformed_lines(self):
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        with os.fdopen(fd, "w") as f:
            f.write('{"type": "user", "message": {"role": "user", "content": "ok"}}\n')
            f.write("not json\n")
            f.write('{"type": "user", "message": {"role": "user", "content": "second"}}\n')
        msgs = parse_messages(path)
        self.assertEqual(len(msgs), 2)


class TestBuildChunks(unittest.TestCase):
    def _msg(self, n: int) -> dict:
        return {"type": "user", "text": "X" * n}

    def test_small_messages_single_chunk(self):
        msgs = [self._msg(1000) for _ in range(5)]
        chunks = build_chunks(msgs, max_chars=80_000, overlap=0)
        self.assertEqual(len(chunks), 1)
        self.assertEqual(len(chunks[0]), 5)

    def test_chunks_split_at_message_boundary(self):
        msgs = [self._msg(30_000) for _ in range(5)]  # 150K total
        chunks = build_chunks(msgs, max_chars=80_000, overlap=0)
        # Each chunk must be <= 80K and contain whole messages
        for ch in chunks:
            total = sum(len(m["text"]) for m in ch)
            self.assertLessEqual(total, 80_000)
        # All messages preserved across chunks (no message lost)
        flattened = [m for ch in chunks for m in ch]
        self.assertEqual(len(flattened), 5)

    def test_chunk_count_is_minimal(self):
        msgs = [self._msg(20_000) for _ in range(10)]  # 200K total
        chunks = build_chunks(msgs, max_chars=80_000, overlap=0)
        # 200K / 80K = need 3 chunks (4 msgs + 4 msgs + 2 msgs)
        self.assertEqual(len(chunks), 3)

    def test_oversized_single_message_passed_through(self):
        # KR4 will handle splitting; KR2 just needs to not crash
        msgs = [self._msg(100_000)]
        chunks = build_chunks(msgs, max_chars=80_000, overlap=0)
        # Single oversized message becomes its own chunk
        self.assertEqual(len(chunks), 1)
        self.assertEqual(len(chunks[0]), 1)

    def test_empty_input(self):
        self.assertEqual(build_chunks([], max_chars=80_000, overlap=0), [])

    def test_overlap_repeats_last_n_messages(self):
        # 10 messages of 20K each → without overlap = 3 chunks (4+4+2)
        # with overlap=2: chunk2 starts with last 2 of chunk1, etc.
        msgs = [{"type": "user", "text": f"M{i}" + "X" * 20_000} for i in range(10)]
        chunks = build_chunks(msgs, max_chars=80_000, overlap=2)
        self.assertGreaterEqual(len(chunks), 2)
        # The first 2 messages of chunk N+1 must equal the last 2 of chunk N
        for i in range(len(chunks) - 1):
            tail = chunks[i][-2:]
            head = chunks[i + 1][:2]
            self.assertEqual([m["text"] for m in tail], [m["text"] for m in head])

    def test_split_large_messages_passthrough_small(self):
        msgs = [{"type": "user", "text": "small"}]
        out = split_large_messages(msgs, max_chars=80_000)
        self.assertEqual(out, msgs)

    def test_split_large_messages_breaks_oversized(self):
        # 200K message at 80K limit → should yield 3 parts
        big = "A" * 200_000
        msgs = [{"type": "user", "text": big}]
        out = split_large_messages(msgs, max_chars=80_000)
        self.assertEqual(len(out), 3)
        # Each part must be <= 80K including marker
        for part in out:
            self.assertLessEqual(len(part["text"]), 80_000)
        # Markers must be present
        markers = [p["text"][:50] for p in out]
        self.assertTrue(any("LARGE MESSAGE 1/3" in m for m in markers))
        self.assertTrue(any("LARGE MESSAGE 2/3" in m for m in markers))
        self.assertTrue(any("LARGE MESSAGE 3/3" in m for m in markers))

    def test_split_large_messages_lossless(self):
        big = "".join(chr(65 + (i % 26)) for i in range(200_000))
        msgs = [{"type": "user", "text": big}]
        out = split_large_messages(msgs, max_chars=80_000)
        # Concatenating part bodies (after stripping marker prefix) recovers original
        recovered = ""
        for p in out:
            body = p["text"].split("\n", 1)[1] if "\n" in p["text"] else ""
            recovered += body
        self.assertEqual(recovered, big)

    def test_split_preserves_message_type(self):
        msgs = [{"type": "assistant", "text": "Z" * 200_000}]
        out = split_large_messages(msgs, max_chars=80_000)
        for p in out:
            self.assertEqual(p["type"], "assistant")

    def test_overlap_does_not_lose_messages(self):
        msgs = [{"type": "user", "text": f"M{i}" + "X" * 20_000} for i in range(10)]
        chunks = build_chunks(msgs, max_chars=80_000, overlap=2)
        # Every original message must appear in at least one chunk
        seen = set()
        for ch in chunks:
            for m in ch:
                seen.add(m["text"])
        self.assertEqual(len(seen), 10)


if __name__ == "__main__":
    unittest.main()
