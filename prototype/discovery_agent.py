"""Discovery Agent prototype - validates whether an LLM can reliably detect
contradictions in client requirements when checked against an explicit,
structured state (instead of relying on free-text conversation memory).

Usage:
    pip install -r requirements.txt
    export ANTHROPIC_API_KEY=...
    python discovery_agent.py
"""

from __future__ import annotations

import json
from typing import Literal

import anthropic
from pydantic import BaseModel, Field

MODEL = "claude-opus-5"

SYSTEM_PROMPT = """\
You are a functional analyst conducting requirements discovery with a client.

You receive the current structured discovery state (stakeholders, processes,
confirmed business rules) and the client's latest statement.

Do the following, in order:
1. Extract any new stakeholders or processes mentioned in the statement.
2. Extract any new business rule candidates stated by the client.
3. Compare the statement and the new rule candidates against every EXISTING
   confirmed business rule. Flag a contradiction whenever the new statement
   would change the behavior for a case an existing rule already covers -
   including implicit conflicts, not just explicit negations.
4. For every contradiction, reference the exact id of the existing rule,
   explain the conflict in one sentence, and write a clarifying question that
   would resolve the ambiguity with the client.

Never resolve a contradiction yourself - always ask the client.
Extract facts only from what the client actually said; do not invent details.
Write extracted rule text, explanations, and clarifying questions in the same
language the client used.
"""


class BusinessRule(BaseModel):
    id: str
    text: str
    source_turn: int
    status: Literal["confirmed", "pending_clarification"]


class DiscoveryState(BaseModel):
    stakeholders: list[str] = Field(default_factory=list)
    processes: list[str] = Field(default_factory=list)
    business_rules: list[BusinessRule] = Field(default_factory=list)
    open_questions: list[str] = Field(default_factory=list)

    def as_context(self) -> str:
        return self.model_dump_json(indent=2)


class Contradiction(BaseModel):
    conflicting_rule_id: str
    explanation: str
    clarifying_question: str


class TurnAnalysis(BaseModel):
    new_stakeholders: list[str] = Field(default_factory=list)
    new_processes: list[str] = Field(default_factory=list)
    new_rules: list[str] = Field(default_factory=list)
    contradictions: list[Contradiction] = Field(default_factory=list)


def analyze_turn(client: anthropic.Anthropic, state: DiscoveryState, statement: str) -> TurnAnalysis:
    response = client.messages.parse(
        model=MODEL,
        max_tokens=2000,
        system=SYSTEM_PROMPT,
        messages=[
            {
                "role": "user",
                "content": (
                    f"Current discovery state:\n{state.as_context()}\n\n"
                    f"New client statement:\n{statement}"
                ),
            }
        ],
        output_format=TurnAnalysis,
    )
    return response.parsed_output


def merge_turn(state: DiscoveryState, turn_index: int, analysis: TurnAnalysis) -> None:
    for stakeholder in analysis.new_stakeholders:
        if stakeholder not in state.stakeholders:
            state.stakeholders.append(stakeholder)

    for process in analysis.new_processes:
        if process not in state.processes:
            state.processes.append(process)

    has_contradiction = bool(analysis.contradictions)

    for contradiction in analysis.contradictions:
        for rule in state.business_rules:
            if rule.id == contradiction.conflicting_rule_id:
                rule.status = "pending_clarification"
        state.open_questions.append(contradiction.clarifying_question)

    next_id = len(state.business_rules) + 1
    for rule_text in analysis.new_rules:
        rule_id = f"RN-{next_id:02d}"
        next_id += 1
        state.business_rules.append(
            BusinessRule(
                id=rule_id,
                text=rule_text,
                source_turn=turn_index,
                status="pending_clarification" if has_contradiction else "confirmed",
            )
        )


def print_turn_result(turn_index: int, statement: str, analysis: TurnAnalysis) -> None:
    print(f"\n--- Turn {turn_index} ---")
    print(f"Client: {statement}")
    if analysis.new_rules:
        print("New candidate rules:")
        for rule in analysis.new_rules:
            print(f"  - {rule}")
    if analysis.contradictions:
        print("CONTRADICTIONS DETECTED:")
        for contradiction in analysis.contradictions:
            print(f"  vs {contradiction.conflicting_rule_id}: {contradiction.explanation}")
            print(f"  -> {contradiction.clarifying_question}")
    else:
        print("No contradictions detected.")


def print_state(state: DiscoveryState) -> None:
    print("\n=== Discovery state ===")
    print(state.model_dump_json(indent=2))


SAMPLE_TRANSCRIPT = [
    "Necesito un sistema para que mis vendedores puedan cargar pedidos desde el celular "
    "y que administracion pueda verlos.",
    "Los vendedores pueden modificar cualquier pedido.",
    "Una vez aprobado, el pedido queda cerrado.",
]


def main() -> None:
    client = anthropic.Anthropic()
    state = DiscoveryState()

    for turn_index, statement in enumerate(SAMPLE_TRANSCRIPT, start=1):
        analysis = analyze_turn(client, state, statement)
        merge_turn(state, turn_index, analysis)
        print_turn_result(turn_index, statement, analysis)

    print_state(state)


if __name__ == "__main__":
    main()
