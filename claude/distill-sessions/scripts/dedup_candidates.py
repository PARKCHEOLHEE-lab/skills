"""Parse dedup responses from LLM output."""
import argparse
import json
import re
import sys


def build_dedup_prompt(candidates: list[dict]) -> str:
    """Build a prompt instructing an LLM to merge semantically duplicate candidates.

    Returns an empty string when there are no candidates.
    """
    if not candidates:
        return ""

    candidates_json = json.dumps(candidates, ensure_ascii=False, indent=2)

    return (
        "You are deduplicating memory candidates extracted from past sessions.\n"
        "\n"
        "Task: merge semantically duplicate candidates. When two or more candidates "
        "describe the same underlying fact or idea, merge them into a single entry "
        "and keep the richest, most informative phrasing for each field. Do not drop "
        "unique candidates.\n"
        "\n"
        "Output ONLY a JSON array of the deduplicated candidates. Each element must "
        "be an object with exactly these fields: \"type\", \"title\", \"content\", "
        "\"why\". Do not wrap the JSON array in markdown, prose, or code fences.\n"
        "\n"
        "Candidates:\n"
        f"{candidates_json}\n"
    )


def parse_dedup_response(text: str) -> list[dict]:
    """Parse an LLM response containing a JSON array of dedup candidates.

    Strips markdown code fences, ignores surrounding prose, and returns only
    dict elements from the parsed array. Returns [] on any parse failure.
    """
    if not isinstance(text, str):
        return []

    stripped = text.strip()

    # Strip surrounding ```json ... ``` or ``` ... ``` code fences.
    fence_match = re.match(
        r"^```(?:json)?\s*\n?(.*?)\n?```\s*$",
        stripped,
        re.DOTALL,
    )
    if fence_match:
        stripped = fence_match.group(1).strip()

    # Find the outermost JSON array.
    start = stripped.find("[")
    end = stripped.rfind("]")
    if start == -1 or end == -1 or end < start:
        return []

    snippet = stripped[start : end + 1]

    try:
        parsed = json.loads(snippet)
    except (ValueError, TypeError):
        return []

    if not isinstance(parsed, list):
        return []

    return [item for item in parsed if isinstance(item, dict)]


def dedup_candidates_main(argv: list[str], claude_runner) -> int:
    parser = argparse.ArgumentParser(description="Deduplicate memory candidates via LLM.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--model", default="sonnet")

    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return int(exc.code) if exc.code is not None else 2

    try:
        with open(args.input, "r", encoding="utf-8") as f:
            candidates = json.load(f)
    except FileNotFoundError:
        print(f"error: input file not found: {args.input}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"error: could not read input file {args.input}: {exc}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: malformed JSON in {args.input}: {exc}", file=sys.stderr)
        return 1

    if not isinstance(candidates, list):
        print(
            f"error: expected a JSON array in {args.input}, got {type(candidates).__name__}",
            file=sys.stderr,
        )
        return 1

    if len(candidates) == 0:
        result: list[dict] = []
    else:
        prompt = build_dedup_prompt(candidates)
        response_text = claude_runner(prompt, args.model)
        result = parse_dedup_response(response_text)

    try:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
    except OSError as exc:
        print(f"error: could not write output file {args.output}: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    import subprocess

    def _real_runner(prompt: str, model: str) -> str:
        result = subprocess.run(
            ["claude", "-p", prompt, "--model", model, "--permission-mode", "default"],
            capture_output=True,
            text=True,
        )
        return result.stdout

    sys.exit(dedup_candidates_main(sys.argv[1:], _real_runner))
