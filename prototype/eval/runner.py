"""Eval runner for the discovery-agent skill's contradiction detection.

Drives the real skill through the Claude Agent SDK (one isolated Claude Code
session per case, with .claude/skills/discovery-agent/ copied into a scratch
cwd) instead of re-implementing the prompt against the raw API - this is the
same skill that ships in the project.

Usage:
    python runner.py            # run every case in cases.json
    python runner.py --only case_01_baseline_no_conflict
"""

from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import tempfile
import time
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    TextBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage,
    query,
)

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SKILL_SRC = PROJECT_ROOT / ".claude" / "skills" / "discovery-agent"
CASES_FILE = Path(__file__).resolve().parent / "cases.json"
FLOW_DIR = PROJECT_ROOT / ".claude" / "hillclimb" / "discovery-contradiction" / "baseline"
ACTOR_MODEL = "claude-sonnet-5"
JUDGE_MODEL = "claude-haiku-4-5"


def build_prompt(turns: list[str]) -> str:
    numbered = "\n".join(f'{i + 1}. "{t}"' for i, t in enumerate(turns))
    return (
        "Use the discovery-agent skill. This is an automated validation run, not a live "
        "interview: there is no real client to wait for between turns. Process this fixed "
        f"transcript, one statement per turn, in order:\n{numbered}\n"
        "Follow the skill's rules exactly (persist discovery-state.json, never resolve a "
        "contradiction yourself). After the last turn, stop."
    )


def predicted_contradiction(state: dict | None) -> bool | None:
    if state is None:
        return None
    if state.get("open_questions"):
        return True
    return any(r.get("status") == "pending_clarification" for r in state.get("business_rules", []))


async def run_case(case: dict) -> dict:
    case_dir = Path(tempfile.mkdtemp(prefix=f"discovery-eval-{case['id']}-"))
    skill_dst = case_dir / ".claude" / "skills" / "discovery-agent"
    skill_dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SKILL_SRC, skill_dst)

    prompt = build_prompt(case["turns"])
    options = ClaudeAgentOptions(
        cwd=str(case_dir),
        skills=["discovery-agent"],
        permission_mode="bypassPermissions",
        model=ACTOR_MODEL,
        max_turns=20,
    )

    trace: list[dict] = [{"role": "user", "content": prompt}]
    result_msg: ResultMessage | None = None
    t0 = time.monotonic()
    try:
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        trace.append({"role": "assistant", "content": block.text})
                    elif isinstance(block, ToolUseBlock):
                        trace.append(
                            {"role": "tool_call", "name": block.name, "content": json.dumps(block.input)}
                        )
            elif isinstance(message, UserMessage):
                content = message.content if isinstance(message.content, list) else []
                for block in content:
                    if isinstance(block, ToolResultBlock):
                        trace.append({"role": "tool_result", "content": str(block.content)})
            elif isinstance(message, ResultMessage):
                result_msg = message
    except Exception as exc:  # noqa: BLE001 - eval harness: capture and record, never crash the batch
        return {"case": case, "error": str(exc), "case_dir": case_dir, "trace": trace}

    duration_s = time.monotonic() - t0

    state_file = case_dir / "discovery-state.json"
    state = None
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            state = None

    return {
        "case": case,
        "result_msg": result_msg,
        "state": state,
        "duration_s": duration_s,
        "case_dir": case_dir,
        "trace": trace,
    }


async def judge_question(case: dict, state: dict | None) -> tuple[int | None, str]:
    if not case["expected_contradiction"]:
        return None, ""
    questions = (state or {}).get("open_questions") or []
    if not questions:
        return 0, "no clarifying question was produced"

    turns_text = "\n".join(f"- {t}" for t in case["turns"])
    prompt = (
        "You are grading one clarifying question from a requirements-discovery agent.\n"
        f"Client statements so far:\n{turns_text}\n\n"
        f'Clarifying question the agent asked:\n"{questions[0]}"\n\n'
        "Does this question correctly identify the real conflict between the statements, stay "
        "genuinely open (it does not assume or state the answer), and is it in Spanish? Reply "
        "with exactly one line: PASS or FAIL, followed by a dash and a one-sentence reason."
    )
    options = ClaudeAgentOptions(model=JUDGE_MODEL, tools=[], permission_mode="bypassPermissions", max_turns=1)
    verdict_text = ""
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    verdict_text += block.text
    verdict_text = verdict_text.strip()
    score = 1 if verdict_text.upper().startswith("PASS") else 0
    return score, verdict_text


def write_trace(case_id: str, trace: list[dict]) -> None:
    traces_dir = FLOW_DIR / "traces"
    traces_dir.mkdir(parents=True, exist_ok=True)
    (traces_dir / f"{case_id}_rep0.json").write_text(
        json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8"
    )


async def process_case(case: dict) -> dict:
    outcome = await run_case(case)
    if "error" in outcome:
        return {"kind": "error", "case": case, "detail": outcome["error"]}

    state = outcome["state"]
    predicted = predicted_contradiction(state)
    if predicted is None:
        return {"kind": "error", "case": case, "detail": "discovery-state.json missing or unreadable"}

    contradiction_correct = int(predicted == case["expected_contradiction"])
    question_quality, question_verdict = await judge_question(case, state)

    result_msg = outcome["result_msg"]
    grade = {"contradiction_correct": contradiction_correct}
    if question_quality is not None:
        grade["question_quality"] = question_quality

    row = {
        "prompt_id": case["id"],
        "prompt": " | ".join(case["turns"]),
        "tags": case["tags"],
        "status": "ok",
        "grade": grade,
        "meta": {
            "expected_contradiction": case["expected_contradiction"],
            "predicted_contradiction": predicted,
            "question_verdict": question_verdict,
        },
        "model": ACTOR_MODEL,
        "usage": (result_msg.usage if result_msg else None),
        "cost_usd": (result_msg.total_cost_usd if result_msg else None),
        "latency_s": round(outcome["duration_s"], 2),
        "num_turns": (result_msg.num_turns if result_msg else None),
    }
    if result_msg and result_msg.model_usage:
        row["meta"]["model_usage_keys"] = list(result_msg.model_usage.keys())
        if ACTOR_MODEL not in "".join(row["meta"]["model_usage_keys"]):
            row["meta"]["model_mismatch_warning"] = True
    write_trace(case["id"], outcome["trace"])
    shutil.rmtree(outcome["case_dir"], ignore_errors=True)
    return {"kind": "ok", "row": row}


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="run a single case id")
    args = parser.parse_args()

    cases = json.loads(CASES_FILE.read_text(encoding="utf-8"))
    if args.only:
        cases = [c for c in cases if c["id"] == args.only]
        if not cases:
            raise SystemExit(f"no case with id {args.only!r}")

    FLOW_DIR.mkdir(parents=True, exist_ok=True)
    results_path = FLOW_DIR / "results.jsonl"
    errors_path = FLOW_DIR / "errors.jsonl"

    results_lines: list[str] = []
    error_lines: list[str] = []
    summary = []

    for case in cases:
        print(f"running {case['id']} ...", flush=True)
        outcome = await process_case(case)
        if outcome["kind"] == "error":
            error_lines.append(json.dumps({"case_id": case["id"], "detail": outcome["detail"]}, ensure_ascii=False))
            print(f"  ERROR: {outcome['detail']}")
            continue
        row = outcome["row"]
        results_lines.append(json.dumps(row, ensure_ascii=False))
        summary.append(row)
        print(
            f"  contradiction_correct={row['grade']['contradiction_correct']} "
            f"cost=${row['cost_usd']} latency={row['latency_s']}s turns={row['num_turns']}"
        )

    if results_lines:
        with results_path.open("a", encoding="utf-8") as f:
            f.write("\n".join(results_lines) + "\n")
    if error_lines:
        with errors_path.open("a", encoding="utf-8") as f:
            f.write("\n".join(error_lines) + "\n")

    if summary:
        n = len(summary)
        correct = sum(r["grade"]["contradiction_correct"] for r in summary)
        total_cost = sum(r["cost_usd"] or 0 for r in summary)
        print(f"\n{correct}/{n} correct. total cost ${total_cost:.4f}")


if __name__ == "__main__":
    asyncio.run(main())
