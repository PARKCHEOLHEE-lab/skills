"""Tests for dedup_candidates."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dedup_candidates import (
    build_dedup_prompt,
    dedup_candidates_main,
    parse_dedup_response,
)


class TestParseDedupResponse(unittest.TestCase):
    def test_parses_plain_json_array(self):
        text = '[{"id": 1, "text": "a"}, {"id": 2, "text": "b"}]'
        result = parse_dedup_response(text)
        self.assertEqual(result, [{"id": 1, "text": "a"}, {"id": 2, "text": "b"}])

    def test_strips_markdown_code_fences(self):
        text = '```json\n[{"id": 1}, {"id": 2}]\n```'
        result = parse_dedup_response(text)
        self.assertEqual(result, [{"id": 1}, {"id": 2}])

    def test_ignores_leading_and_trailing_prose(self):
        text = (
            "Sure, here are the deduplicated candidates you asked for:\n"
            '[{"id": 1, "keep": true}, {"id": 2, "keep": false}]\n'
            "Let me know if you need anything else."
        )
        result = parse_dedup_response(text)
        self.assertEqual(
            result,
            [{"id": 1, "keep": True}, {"id": 2, "keep": False}],
        )

    def test_returns_empty_on_malformed_json(self):
        text = "[this is not, valid json at all }"
        result = parse_dedup_response(text)
        self.assertEqual(result, [])

    def test_returns_empty_when_no_array(self):
        text = "I could not find any candidates to return."
        result = parse_dedup_response(text)
        self.assertEqual(result, [])

    def test_filters_non_dict_elements(self):
        text = '[{"a": 1}, "string", 42, {"b": 2}]'
        result = parse_dedup_response(text)
        self.assertEqual(result, [{"a": 1}, {"b": 2}])


class TestBuildDedupPrompt(unittest.TestCase):
    def test_empty_candidates_returns_empty_string(self):
        self.assertEqual(build_dedup_prompt([]), "")

    def test_includes_all_candidate_titles(self):
        candidates = [
            {"type": "fact", "title": "First title", "content": "c1", "why": "w1"},
            {"type": "fact", "title": "Second title", "content": "c2", "why": "w2"},
            {"type": "fact", "title": "Third title", "content": "c3", "why": "w3"},
        ]
        prompt = build_dedup_prompt(candidates)
        for c in candidates:
            self.assertIn(c["title"], prompt)

    def test_instructs_json_array_output(self):
        candidates = [{"type": "fact", "title": "t", "content": "c", "why": "w"}]
        prompt = build_dedup_prompt(candidates)
        self.assertIn("JSON array", prompt)

    def test_instructs_merging_duplicates(self):
        candidates = [{"type": "fact", "title": "t", "content": "c", "why": "w"}]
        prompt = build_dedup_prompt(candidates)
        self.assertIn("merge", prompt.lower())

    def test_preserves_non_ascii_in_candidate_json(self):
        candidates = [
            {"type": "fact", "title": "한글 제목", "content": "내용", "why": "이유"}
        ]
        prompt = build_dedup_prompt(candidates)
        self.assertIn("한글 제목", prompt)
        self.assertNotIn("\\uD55C", prompt)


class TestDedupCandidatesMain(unittest.TestCase):
    def setUp(self):
        self._tempfiles = []

    def tearDown(self):
        for path in self._tempfiles:
            try:
                os.remove(path)
            except OSError:
                pass

    def _make_temp(self, content: str | None = None) -> str:
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        self._tempfiles.append(path)
        if content is not None:
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
        return path

    def test_empty_input_writes_empty_array_and_skips_runner(self):
        input_path = self._make_temp("[]")
        output_path = self._make_temp()

        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return "[]"

        rc = dedup_candidates_main(
            ["--input", input_path, "--output", output_path],
            fake_runner,
        )

        self.assertEqual(rc, 0)
        self.assertEqual(calls, [])
        with open(output_path, "r", encoding="utf-8") as f:
            self.assertEqual(json.load(f), [])

    def test_happy_path_runs_prompt_and_writes_result(self):
        candidates = [
            {"type": "fact", "title": "Alpha title", "content": "c1", "why": "w1"},
            {"type": "fact", "title": "Bravo title", "content": "c2", "why": "w2"},
            {"type": "fact", "title": "Charlie title", "content": "c3", "why": "w3"},
        ]
        input_path = self._make_temp(json.dumps(candidates))
        output_path = self._make_temp()

        merged = [
            {"type": "fact", "title": "Alpha+Bravo", "content": "m1", "why": "mw1"},
            {"type": "fact", "title": "Charlie title", "content": "c3", "why": "w3"},
        ]
        runner_response = "```json\n" + json.dumps(merged) + "\n```"

        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return runner_response

        rc = dedup_candidates_main(
            ["--input", input_path, "--output", output_path],
            fake_runner,
        )

        self.assertEqual(rc, 0)
        self.assertEqual(len(calls), 1)
        called_prompt = calls[0][0]
        for c in candidates:
            self.assertIn(c["title"], called_prompt)
        with open(output_path, "r", encoding="utf-8") as f:
            self.assertEqual(json.load(f), merged)

    def test_missing_input_file_returns_nonzero(self):
        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return "[]"

        output_path = self._make_temp()
        rc = dedup_candidates_main(
            [
                "--input",
                "/nonexistent/path/definitely_not_here.json",
                "--output",
                output_path,
            ],
            fake_runner,
        )

        self.assertNotEqual(rc, 0)
        self.assertEqual(calls, [])

    def test_malformed_input_json_returns_nonzero(self):
        input_path = self._make_temp('"not a list"')
        output_path = self._make_temp()

        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return "[]"

        rc = dedup_candidates_main(
            ["--input", input_path, "--output", output_path],
            fake_runner,
        )

        self.assertNotEqual(rc, 0)
        self.assertEqual(calls, [])

    def test_default_model_is_sonnet(self):
        candidates = [
            {"type": "fact", "title": "t", "content": "c", "why": "w"},
        ]
        input_path = self._make_temp(json.dumps(candidates))
        output_path = self._make_temp()

        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return "[]"

        rc = dedup_candidates_main(
            ["--input", input_path, "--output", output_path],
            fake_runner,
        )

        self.assertEqual(rc, 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], "sonnet")

    def test_explicit_model_passed_through(self):
        candidates = [
            {"type": "fact", "title": "t", "content": "c", "why": "w"},
        ]
        input_path = self._make_temp(json.dumps(candidates))
        output_path = self._make_temp()

        calls = []

        def fake_runner(prompt: str, model: str) -> str:
            calls.append((prompt, model))
            return "[]"

        rc = dedup_candidates_main(
            [
                "--input",
                input_path,
                "--output",
                output_path,
                "--model",
                "haiku",
            ],
            fake_runner,
        )

        self.assertEqual(rc, 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1], "haiku")


if __name__ == "__main__":
    unittest.main()
