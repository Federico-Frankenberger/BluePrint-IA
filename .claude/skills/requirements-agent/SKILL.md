---
name: requirements-agent
description: "Trigger: requirements agent, generar requisitos, RF RNF, requisitos funcionales, iniciar requirements. Turns confirmed state/discovery-state.json rules/processes into traceable RF/RNF requirements, blocking anything still pending_clarification and rejecting anything ruled out by state/prd-state.json's out_of_scope."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.2"
---

## Activation Contract

Load when the user runs `/requirements-agent`, asks to generate functional/non-functional requirements, or asks to review `state/requirements-state.json` for this project.

## Hard Rules

- Never generate a requirement from a business rule whose `status` is `pending_clarification`, or from anything not yet confirmed. Discovery's contradiction gate must resolve first.
- Every requirement carries `status: "confirmed"` plus an explicit `source` (a business rule id or a process name). Never write an orphan requirement.
- If `state/prd-state.json` exists and a candidate requirement's source rule/process matches an entry in its `out_of_scope`, do not confirm it as a normal RF/RNF — record it in `rejected` with `status: "rejected"` and `reason: "prd_out_of_scope: <item>"`, quoting the exact PRD out-of-scope item. This is a permanent exclusion, not a `blocked` (waiting-on-something) case — never mix the two lists.
- A rule still `status: pending_clarification` upstream is not rejected — it's `blocked`. Record it in `blocked` with `status: "blocked"` and `reason: "upstream rule still pending_clarification"`, and mirror it as one entry in this file's own `open_questions` (`{id, question, item_ref}`, `item_ref` = the rule id).
- Classify each requirement as exactly one of `RF` (functional - what the system does) or `RNF` (non-functional - a quality or constraint). Never mix the two in one entry.
- Persist state after every run. Read the existing `state/requirements-state.json` first; add or update by `source`, never duplicate or overwrite from scratch.
- If `state/discovery-state.json` has zero confirmed rules or processes, do not fabricate requirements - report that Discovery isn't ready yet.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/discovery-state.json` in project root | Stop. Tell the user to run `/discovery-agent` first. |
| No `state/prd-state.json` in project root | Proceed using `state/discovery-state.json` only; note in the final report that the PRD scope gate wasn't applied. |
| Confirmed rule or process not yet mapped to a requirement, and not in `state/prd-state.json.out_of_scope` | Generate one `RF-##` or `RNF-##`, id assigned per type, `status: "confirmed"`, with its `source`. |
| Confirmed rule or process matches an entry in `state/prd-state.json.out_of_scope` | Do not generate a requirement; record in `rejected` with `status: "rejected"`, `reason: "prd_out_of_scope: <item>"`. |
| Rule `status: pending_clarification` | Skip it; record in `blocked` with `status: "blocked"` and a reason, and mirror it in `open_questions`. |
| Discovery state changed since last run (new confirmed rules) | Add only the new requirements; keep existing `RF-##`/`RNF-##` ids stable. |

## Execution Steps

1. Load `state/discovery-state.json` from the project root (apply the missing-file Decision Gate if absent).
2. Load `state/prd-state.json` if present (optional — schema in `../prd-agent/assets/prd-state.schema.json`); if absent, proceed with discovery only and note it in the final report.
3. Load or initialize `state/requirements-state.json` (schema in `assets/requirements-state.schema.json`).
4. For each confirmed rule/process without a mapped requirement, first check it against `state/prd-state.json.out_of_scope` (if loaded); if it matches, skip drafting and record it in `rejected` per the Hard Rule above.
5. For everything else, classify `RF` vs `RNF` and draft the requirement text with `status: "confirmed"`.
6. Skip and record any `pending_clarification` rule in `blocked`, and mirror it in `open_questions`.
7. Assign the next `RF-##`/`RNF-##` id per type; attach the `source` reference.
8. Write the full state back to `state/requirements-state.json`.
9. Report: requirements added (with source), what's `rejected` (PRD-scope) vs `blocked` (waiting on upstream) and why, and the traceability link back to Discovery and PRD.

## Output Contract

Each run ends with the updated `state/requirements-state.json` on disk, a short summary of new `RF`/`RNF` entries with their source, and the `rejected`/`blocked` lists when non-empty — keeping PRD-scope exclusions (`rejected`) and upstream-pending items (`blocked`) clearly distinct. On request, output the full file as the handoff artifact for the next pipeline stage (User Stories).

## References

- `../discovery-agent/SKILL.md` — upstream stage; the `state/discovery-state.json` contract this skill reads.
- `../prd-agent/SKILL.md` — optional upstream stage; `state/prd-state.json`'s `out_of_scope` gates requirement generation when present.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline this stage feeds into.
- `assets/requirements-state.schema.json` — state file shape.
