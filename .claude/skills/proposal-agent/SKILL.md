---
name: proposal-agent
description: "Trigger: proposal agent, generar propuesta, propuesta comercial, iniciar proposal. Writes the client-facing source/propuesta.md from state/prd-state.json's in/out of scope and state/estimation-state.json, never inventing scope, resolutions to open questions, or a dollar figure."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.3"
---

## Activation Contract

Load when the user runs `/proposal-agent`, asks to generate the commercial proposal, or asks to review `source/propuesta.md` / `state/proposal-state.json` for this project.

## Hard Rules

- Read `prd-state.json.engagement_type` first and branch the whole output on it. `client` mode produces the full commercial proposal (Alcance, Fuera de alcance, Metodología, Estimación, Inversión) as below. `own_product` mode produces an internal decision-summary instead (Alcance confirmado, Fuera de alcance, Estimación, Supuestos sin validar, and a pending "¿avanzar a desarrollo?" line) — no Metodología section, no Inversión section, no `$X` figures of any kind, since there's no external party to quote. Everything else in this file (how Alcance/Fuera de alcance/Estimación are sourced and traced) applies the same in both modes; only the surrounding document shape and the presence/absence of pricing differs.
- Every item in "Alcance" traces to a confirmed `in_scope` entry in `state/prd-state.json`. For each PRD in-scope item, list the `HU-##`(s) that implement it (cross-reference `HU.source` → `RF-##` → `RF.source` against the PRD item's `source`). Never invent scope beyond what `state/prd-state.json` and `state/user-stories-state.json` actually contain.
- "Fuera de alcance" is built primarily, verbatim, from `state/prd-state.json.out_of_scope` (item + reason) — PRD is the authoritative scope boundary, not a reconstruction from HU/blocked state.
- Anything genuinely `blocked` or left as an open question upstream (`state/discovery-state.json`, `state/requirements-state.json`, `state/uml-state.json`, `state/estimation-state.json`) that PRD's scope lists haven't already covered goes in a separate "A definir en el arranque" list — never silently dropped, never folded into "Fuera de alcance" as if PRD had ruled on it.
- `state/requirements-state.json.rejected` entries (PRD-out-of-scope exclusions) must never appear in "A definir en el arranque" — they're already represented in "Fuera de alcance" via PRD directly. Only genuine `blocked` (upstream-pending) and `open_questions` entries belong in "A definir en el arranque".
- A PRD in-scope item with unresolved `open_questions` on its supporting `HU-##` can still be in scope - state the open item in "A definir en el arranque". Never invent a resolution for it in the proposal text.
- "Estimación" carries over `state/estimation-state.json`'s duration range, team, and uncertainty level verbatim. Never collapse a range into a single fake-precise number.
- "Inversión" (`client` mode only) is never a fabricated dollar figure. No rate card exists upstream in this pipeline, so it stays an explicit placeholder (`$X` per line item) for the user to fill in with their own rates. `own_product` mode has no "Inversión" section at all — replace it with "Supuestos sin validar" (count/list of anything still `pending_clarification` upstream) and a closing "Decisión: ¿avanzar a desarrollo? — pendiente de confirmación del fundador" line. This skill never makes that go/no-go decision itself.
- Persist `state/proposal-state.json` after every run: which PRD `in_scope`/`out_of_scope` items were used, with their `HU-##` cross-references. Read existing files first; regenerate `source/propuesta.md` in full each run (it's a document, not an incremental log), but never overwrite `state/proposal-state.json`'s history without reflecting current source state.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/prd-state.json` | Stop. Tell the user to run `/prd-agent` first. |
| No `state/estimation-state.json` | Stop. Tell the user to run `/estimation-agent` first. |
| `state/prd-state.json.in_scope` item with one or more `HU-##` mapped to it | Include in "Alcance", listing its supporting `HU-##`(s). |
| `state/prd-state.json.in_scope` item with no `HU-##` mapped yet | Include in "Alcance" as a committed item, flagged that user stories are still pending — a traceability gap to surface, not hide. |
| `state/prd-state.json.out_of_scope` item | List verbatim in "Fuera de alcance" with its `reason`. |
| `HU-##` with unresolved `open_questions` | Keep in "Alcance" via its PRD item, but add its open item to "A definir en el arranque" - not silently resolved. |
| `state/uml-state.json.blocked`, `state/requirements-state.json.blocked`, or leftover `state/discovery-state.json`/`state/estimation-state.json` `open_questions` not covered by PRD's scope lists | List in "A definir en el arranque", never drop silently. |
| `state/requirements-state.json.rejected` entry | Do not list in "A definir en el arranque" — already covered by PRD's `out_of_scope` in "Fuera de alcance". |
| No pricing/rate data anywhere upstream, `client` mode | Leave "Inversión" as a labeled placeholder; never invent a number. |
| `state/prd-state.json.engagement_type == "own_product"` | Skip "Metodología" and "Inversión" entirely; render "Supuestos sin validar" from upstream `pending_clarification` items and end with the pending go/no-go line instead. |

## Execution Steps

1. Load `state/discovery-state.json`, `state/prd-state.json`, `state/requirements-state.json`, `state/user-stories-state.json`, `state/estimation-state.json` (apply the missing-file gates for `state/prd-state.json` and `state/estimation-state.json` if absent).
2. Load or initialize `state/proposal-state.json` (schema in `assets/proposal-state.schema.json`).
3. Build "Alcance" from every `state/prd-state.json.in_scope` item, cross-referencing which `HU-##` implement it; flag PRD items with no `HU-##` yet.
4. Build "Fuera de alcance" verbatim from `state/prd-state.json.out_of_scope`.
5. Build "A definir en el arranque" from any upstream `blocked`/`open_questions` (discovery, requirements, uml, estimation) not already covered by PRD's scope lists, plus any `HU-##` open items — explicitly excluding `state/requirements-state.json.rejected`, which already lives in "Fuera de alcance".
6. Copy "Estimación" verbatim from `state/estimation-state.json` (range, team, uncertainty).
7. Branch on `state/prd-state.json.engagement_type`: `client` writes "Metodología" + "Inversión" as a labeled placeholder, never a number; `own_product` skips both and instead writes "Supuestos sin validar" (from upstream `pending_clarification` items) plus the pending go/no-go line.
8. Write the full `source/propuesta.md` and update `state/proposal-state.json`.
9. Report: what's in scope (with PRD source and HU refs), what's out of scope per PRD, what's flagged in "A definir en el arranque", and — per mode — either that "Inversión" needs the user's own rates, or that the go/no-go decision is pending the founder.

## Output Contract

Each run ends with `source/propuesta.md` (the client-facing document) and `state/proposal-state.json` (PRD-to-HU scope traceability) on disk, plus a short summary in chat of scope / open items / what still needs rates.

## References

- `../prd-agent/SKILL.md` — upstream `state/prd-state.json` contract; authoritative source for "Alcance" / "Fuera de alcance".
- `../estimation-agent/SKILL.md` — upstream `state/estimation-state.json` contract (range, team, uncertainty, assumptions).
- `../user-stories-agent/SKILL.md` — upstream `state/user-stories-state.json` contract (HU cross-reference for PRD scope items).
- `../../../ingenieria_requerimientos_agentica.md` — overall pipeline; proposal structure (section 10).
- `assets/proposal-state.schema.json` — state file shape.
