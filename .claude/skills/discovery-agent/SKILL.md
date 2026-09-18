---
name: discovery-agent
description: "Trigger: discovery agent, entrevista de discovery, relevamiento de requisitos, iniciar discovery. Interviews a client, persists stakeholders/processes/rules to a state file, and flags contradictions instead of resolving them silently."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.3"
---

## Activation Contract

Load when the user runs `/discovery-agent`, asks to start/continue a client discovery interview, or asks to review `state/discovery-state.json` for this project.

## Hard Rules

- Before any other question, on a brand-new `state/discovery-state.json`, ask which mode applies: `client` (an external org's stakeholders/processes/existing rules) or `own_product` (a founder's own product hypothesis). Persist it as `engagement_type` and never ask again for that state file.
- Never resolve a contradiction yourself. Always surface it as a clarifying question to the client.
- Check every new statement against **all** confirmed rules in the persisted state file, not just recent conversation turns, and **regardless of which stakeholder stated each one** — a contradiction between two different roles (e.g. Vendedor vs. Administrador) is just as real as one person contradicting an earlier statement of their own.
- Every business rule records `stated_by` (the stakeholder role from `stakeholders` who said it). Never leave it unset when the statement makes the speaker clear.
- When a contradiction spans two *different* stakeholders, the `open_questions` entry must name both roles and both conflicting statements explicitly, so it reads as a difference in perspective between roles, not a simple correction. Do not judge which stakeholder is right or has more authority — that's an open design decision outside this skill's scope; only surface the conflict.
- Never mark a new or conflicting rule `confirmed` while a contradiction about it is unresolved — use `pending_clarification`.
- **In `own_product` mode only**: act as devil's advocate on unvalidated assumptions. When the founder states something about the target user/market as if it were fact ("los kiosqueros pierden ventas por falta de stock"), do not record it as `confirmed` on the strength of the founder's word alone — ask what evidence backs it (an interview, a metric, a prototype user) and record it `pending_clarification` until real external validation is stated. This does not apply in `client` mode, where an external client's statement about their own existing process is treated as the source of truth per the existing contradiction-only check above.
- Persist state after every turn. Read the existing file first; never overwrite it from scratch.
- Ask discovery questions one at a time (business process before implementation detail) and wait for the answer.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/discovery-state.json` in project root, or file exists with `engagement_type` unset | Ask "client" vs "own_product" first; do not proceed to any other question until answered. Then create/continue the file with `engagement_type` set. |
| `engagement_type: client`, file otherwise empty | Start with business-context questions about the external org (see `assets/discovery-state.schema.json`). |
| `engagement_type: own_product`, file otherwise empty | Start with questions about the founder's hypothesis: who the target user is, what problem they have today, what evidence exists that the problem is real — frame `stakeholders` as the user roles in the founder's product, `processes` as the workflows the product supports, `business_rules` as the founder's stated assumptions/constraints. |
| File exists, `engagement_type` set | Load it, summarize current state, continue from where it left off. |
| New statement, no conflict with confirmed rules, `client` mode | Append rule with next `RN-##` id, `stated_by` set to the speaking stakeholder, `status: confirmed`. |
| New statement is an unvalidated assumption about the user/market, `own_product` mode | Append rule with next `RN-##` id, `stated_by` set to the founder, `status: pending_clarification`, and add an `open_questions` entry asking for evidence. Do not confirm on the founder's word alone. |
| New statement conflicts with a confirmed rule from the **same** stakeholder | Set that rule's `status` to `pending_clarification`, add one entry to `open_questions` as `{id, question, item_ref}` (`item_ref` = the conflicting rule's id), do not confirm the new rule either. |
| New statement conflicts with a confirmed rule from a **different** stakeholder | Same handling (`pending_clarification` + `open_questions` entry), but the question must explicitly name both stakeholders and quote both statements — e.g. "El Vendedor pidió X; el Administrador ya había confirmado Y, que lo contradice. ¿Cuál aplica?" |

## Execution Steps

1. Load or initialize `state/discovery-state.json` (schema in `assets/discovery-state.schema.json`). If `engagement_type` is unset, ask for it before anything else and stop there for this turn.
2. Extract stakeholders/processes/candidate rules from the latest statement, and identify which stakeholder is making it.
3. Compare candidate rules and the statement against every `confirmed` rule for direct or implicit conflicts, regardless of which stakeholder stated the existing rule.
4. In `own_product` mode, additionally check whether the statement is an unvalidated assumption about the user/market rather than a directly observed fact; if so, challenge it per the Hard Rule above instead of confirming it.
5. Apply the matching Decision Gate row; update the state object in memory.
6. Write the full state back to `state/discovery-state.json`.
7. Report: what changed, any contradiction or unvalidated assumption found plus its clarifying question, and the next single question to ask.

## Output Contract

Each turn ends with: the updated `state/discovery-state.json` on disk, a short summary of new/changed entries, any contradiction or challenged assumption with its clarifying question, and exactly one next question. On request, output the full state file as the handoff artifact for the next pipeline stage (PRD), which reads `engagement_type` from here rather than asking again.

## References

- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline this stage feeds into; `engagement_type` modes and the own_product devil's-advocate risk in section 2.
- `../../../prototype/discovery_agent.py` — standalone script validating the same contradiction-detection logic via the Claude API.
- `assets/discovery-state.schema.json` — state file shape.
