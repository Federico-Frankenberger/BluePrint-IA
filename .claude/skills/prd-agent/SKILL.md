---
name: prd-agent
description: "Trigger: prd agent, generar prd, product requirement document, in-scope out-of-scope, iniciar prd. Synthesizes confirmed state/discovery-state.json into a PRD (vision, personas, in/out of scope, success criteria), never promoting a pending_clarification item into scope silently."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.2"
---

## Activation Contract

Load when the user runs `/prd-agent`, asks to synthesize/generate the PRD, define in-scope/out-of-scope, or asks to review `source/prd.md` / `state/prd-state.json` for this project.

## Hard Rules

- Never move a business rule or process whose Discovery `status` is `pending_clarification` into "In-Scope" or "Out-of-Scope". It stays in this skill's own `open_questions` until Discovery resolves it — silence is not a decision.
- Every "In-Scope" item traces to a confirmed `RN-##` rule or a named process from `state/discovery-state.json`. Never invent scope beyond what Discovery actually confirmed.
- Every persona traces to a `stakeholder` entry in `state/discovery-state.json`. Never invent a persona Discovery never mentioned.
- Read `engagement_type` from `state/discovery-state.json` and carry it into `state/prd-state.json` — Discovery is now the source of truth for the mode, this skill does not ask independently. Fallback only: if an old `state/discovery-state.json` predates this field and has it unset, ask the user once which mode applies, persist the answer in `state/prd-state.json`, and note in the report that Discovery is missing the field (a gap in that upstream file, not something to silently patch there).
- Persist state after every run. Read the existing `state/prd-state.json` first; add or update by source, never duplicate or overwrite from scratch. Regenerate `source/prd.md` in full each run (it's a document, not an incremental log).

## Decision Gates

| Situation | Action |
|---|---|
| No `state/discovery-state.json` in project root | Stop. Tell the user to run `/discovery-agent` first. |
| Discovery has zero confirmed rules/processes | Stop. Report Discovery isn't ready yet — nothing to synthesize. |
| `state/discovery-state.json` has `engagement_type` set | Copy it into `state/prd-state.json` without asking. |
| `state/discovery-state.json` predates this field (unset) | Ask the user once which mode applies, persist to `state/prd-state.json`, note the upstream gap in the report. |
| Confirmed rule or process not yet reflected in scope | Add to "In-Scope", with its source. |
| Rule/process `status: pending_clarification` | Do not place in scope or out-of-scope; add/keep in this skill's `open_questions` as `{id, question, item_ref}` (`item_ref` = the rule/process). |
| Stakeholder with no mapped persona | Draft one persona per stakeholder, with its source. |

## Execution Steps

1. Load `state/discovery-state.json` from the project root (apply the missing-file / not-ready Decision Gates if applicable).
2. Load or initialize `state/prd-state.json` (schema in `assets/prd-state.schema.json`). Copy `engagement_type` from `state/discovery-state.json`; only ask if the upstream file itself lacks it (pre-dates this field).
3. Draft "Visión y objetivos" — framed around an external client's need in `client` mode, or the founder's own product hypothesis in `own_product` mode.
4. Derive one persona per confirmed `stakeholder`, with its source.
5. Build "In-Scope" from confirmed rules/processes; keep anything `pending_clarification` out of both scope lists and in `open_questions` (as `{id, question, item_ref}`) instead.
6. Draft "Criterios de éxito" from the confirmed rules and stated objectives — never invent a metric Discovery never implied.
7. Write the full `source/prd.md` and update `state/prd-state.json`.
8. Report: vision/objectives drafted, personas derived (with source), in-scope items (with source), what's still in `open_questions` and why, and the traceability link back to Discovery.

## Output Contract

Each run ends with `source/prd.md` (the strategic document — vision, personas, in/out of scope, success criteria) and `state/prd-state.json` (traceability back to Discovery) on disk, plus a short summary in chat of scope / personas / open items. On request, output the full file as the handoff artifact for the next pipeline stage (Requirements) — `requirements-agent` reads `state/prd-state.json` and gates any candidate requirement against its `out_of_scope`.

## References

- `../discovery-agent/SKILL.md` — upstream stage; the `state/discovery-state.json` contract this skill reads.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline; PRD design in section 3, `engagement_type` mode in section 2.
- `assets/prd-state.schema.json` — state file shape.
