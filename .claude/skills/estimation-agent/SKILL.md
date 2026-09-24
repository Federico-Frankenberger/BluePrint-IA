---
name: estimation-agent
description: "Trigger: estimation agent, estimar, estimación preliminar, iniciar estimation. Breaks confirmed stories into tasks and produces a range-based estimate whose uncertainty is driven by unresolved open_questions/blocked items, never a fake-precise number."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.1"
---

## Activation Contract

Load when the user runs `/estimation-agent`, asks for an estimate, or asks to review `state/estimation-state.json` for this project.

## Hard Rules

- Never output a single precise number (e.g. "47 horas"). Always a duration **range**, a team composition, and an explicit uncertainty level (`low`/`medium`/`high`), with the assumptions behind it in plain language.
- Every task in the breakdown carries an explicit `source` (`HU-##`). Never estimate work with no traceable story.
- Tasks get qualitative complexity (`low`/`medium`/`high`), never invented hour counts.
- Any unresolved `open_questions` on a story, plus unresolved items in `state/discovery-state.json.open_questions` and `state/uml-state.json.blocked`, must be classified into exactly one of `risks`, `assumptions`, or `dependencies` (never collapsed into one generic bucket) and must raise that story's (or the overall) uncertainty level. Never estimate as if the pipeline were fully specified when it isn't.
- **Classification rule** — for each unresolved item, ask: is it something that *might happen* and would hurt the project if it did (→ `risks`, e.g. "el modelo de datos podría cambiar si el cliente agrega un producto compuesto")? Is it something *taken as true without confirmation yet* (→ `assumptions`, e.g. "se asume que el stock se valida en tiempo real")? Or is it something *external that must exist/happen* for the work to proceed (→ `dependencies`, e.g. "depende de que el cliente confirme el proveedor de pagos")? When genuinely ambiguous between two, pick the one that best matches and say so in the item's wording — never invent a fourth bucket.
- Persist state after every run. Read the existing file first; add or update by `source`, never overwrite from scratch.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/user-stories-state.json` | Stop. Tell the user to run `/user-stories-agent` first. |
| `HU-##` with no unresolved `open_questions` | Decompose into tasks (backend/API/DB/frontend/auth/testing as applicable), source-tagged, complexity per task. |
| `HU-##` with unresolved `open_questions` | Decompose what's knowable; classify each open question into that story's `risks`/`assumptions`/`dependencies` per the classification rule; raise its uncertainty level. |
| `state/discovery-state.json.open_questions` or `state/uml-state.json.blocked` non-empty | Classify each into `global_risks`/`global_assumptions`/`global_dependencies`; raise the overall uncertainty level - never scope this to one story alone. |
| Upstream state changed since last run | Re-decompose only the affected `HU-##`; keep other task lists stable. |

## Execution Steps

1. Load `state/user-stories-state.json` (apply the missing-file gate if absent), `state/requirements-state.json`, `state/discovery-state.json`, and `state/uml-state.json`.
2. Load or initialize `state/estimation-state.json` (schema in `assets/estimation-state.schema.json`).
3. For each `HU-##`, decompose into tasks with qualitative complexity; classify its `open_questions` into `risks`/`assumptions`/`dependencies` per the Hard Rule.
4. Collect global items from `state/discovery-state.json.open_questions` and `state/uml-state.json.blocked`, classified the same way into `global_risks`/`global_assumptions`/`global_dependencies`.
5. Derive the overall uncertainty level from the volume and nature of open assumptions (more/critical unresolved items -> higher).
6. Produce the preliminary estimate: duration range, team composition, uncertainty level, full assumptions list.
7. Write `state/estimation-state.json`; report the range, team, uncertainty level, and every assumption driving it.

## Output Contract

Each run ends with the updated `state/estimation-state.json` on disk and a short summary: duration range, team composition, uncertainty level, and the explicit list of assumptions/open items behind that range - never a bare number with no caveats.

## References

- `../user-stories-agent/SKILL.md` — upstream `state/user-stories-state.json` contract and per-story `open_questions`.
- `../uml-agent/SKILL.md` — upstream `state/uml-state.json.blocked` contract.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline; estimation philosophy (section 9).
- `assets/estimation-state.schema.json` — state file shape.
