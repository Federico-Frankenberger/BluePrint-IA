---
name: impact-analysis-agent
description: "Trigger: impact analysis agent, análisis de impacto, change request, cambio post-aprobación, cotizar cambio. Traces a post-approval change request against state/prd-state.json's out_of_scope and the deterministic downstream reference graph, never auto-approving or silently absorbing scope creep."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.1"
---

## Activation Contract

Load when the user runs `/impact-analysis-agent`, reports that the client is asking for new/changed behavior after the proposal was already approved, or asks "qué se rompe si cambiamos X" for an already-confirmed item.

## Hard Rules

- Never decide on your own whether a change request is acceptable. This skill reports contradiction + blast radius; the human always makes the accept/reject/quote call (mirrors the document's section 18 principle: "Generando cotización de Change Request", not "aprobando el cambio").
- Never compute the affected-items graph yourself by reading the `*-state.json` files and reasoning about references. Run `scripts/find-affected.sh <seed-id>` and relay its exact output — this is the same discipline as `orchestrator-agent` and `spec-package-agent`: mechanical traversal is deterministic, not an LLM judgment call.
- Always check the change request's description against every entry in `state/prd-state.json.out_of_scope` first. If it clearly restates or extends something already excluded there, `contradicts_out_of_scope` is `true` and you must quote the exact PRD entry — never soften or reinterpret an out-of-scope item into an in-scope one on your own authority.
- **Also check whether the request asks to change the `priority` of an already-confirmed `RF-##`/`RNF-##`/`HU-##`.** This is a distinct kind of impact from `contradicts_out_of_scope` — it doesn't violate the agreed scope, but it changes what was promised to ship first, which is exactly the kind of decision the manual (§35.2) says the IA never makes alone. When it applies, set `priority_change.applies: true` with the item's current `priority` (`from`, read from `requirements-state.json`/`user-stories-state.json`) and the requested one (`to`), and still trace its blast radius via `find-affected.sh` — a priority bump can ripple into Estimation and Proposal same as a scope change would.
- Identify the closest existing seed id (an `RN-##`, `RF-##`, `RNF-##`, or `HU-##`) the request most relates to from context (discovery/PRD/requirements text) before calling the script — the script needs a concrete seed, it does not do semantic matching itself.
- Default every new change request to `status: "pending_quote"`. Only mark it `rejected` directly when it is a pure restatement of an out-of-scope item with no new negotiable value proposed by the client — and say explicitly why, quoting the PRD entry. When uncertain, leave it `pending_quote`.
- Persist every change request to `state/change-requests-state.json`, even the ones marked `rejected` directly — nothing gets discussed and then dropped silently.
- Never invent affected items beyond what the script actually found. If the script reports "(sin coincidencias)" for a stage, say so plainly — a small or empty blast radius is a valid, useful result, not a failure to search harder.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/prd-state.json` in project root | Stop. Tell the user PRD hasn't been synthesized yet — there's no Out-of-Scope to check a change request against. |
| Change request text matches/extends a `state/prd-state.json.out_of_scope` entry | `contradicts_out_of_scope: true`; quote the exact entry; run the script seeded from the rule/id behind that entry. |
| Change request asks to change the `priority` of an already-confirmed item | `priority_change.applies: true` with `from`/`to`; still run the script seeded from that item's id — a priority change is reported, never auto-applied to `requirements-state.json`/`user-stories-state.json` by this skill. |
| Change request doesn't match any `out_of_scope` entry nor a priority change, but relates to a confirmed `RN-##`/`RF-##`/`HU-##` | `contradicts_out_of_scope: false`, `priority_change.applies: false`; run the script seeded from that id to report the blast radius anyway (even in-scope changes can ripple downstream). |
| Change request doesn't relate to anything confirmed yet (genuinely new ground) | Note that there's no existing seed id to trace — report zero blast radius and flag it as new scope, not a change to existing scope. |
| `scripts/find-affected.sh` reports matches in a stage | Relay them verbatim as the affected items for that stage. |
| `scripts/find-affected.sh` reports "(sin coincidencias)" for a stage | Relay it verbatim; do not manually re-check that stage yourself. |

## Execution Steps

1. Read the change request description from the user.
2. Load `state/prd-state.json`; check the description against every `out_of_scope` entry, and load `state/requirements-state.json`/`state/user-stories-state.json` to check whether it requests a `priority` change on a confirmed item (apply the matching Decision Gate).
3. Identify the closest confirmed seed id the request relates to (from discovery/PRD/requirements text — your own judgment, this part is not scripted).
4. Run `bash .claude/skills/impact-analysis-agent/scripts/find-affected.sh <seed-id>` from the project root via the Bash tool. Relay its output verbatim per stage.
5. Assemble the report in the document's own style (section 18): state whether it contradicts Out-of-Scope, quote the PRD entry if so, and list what's affected per stage from the script's real output — never round the blast radius up or down.
6. Load or initialize `state/change-requests-state.json` (schema in `assets/change-requests-state.schema.json`); append the new `CR-##` entry with `status: "pending_quote"` (or `"rejected"` per the Hard Rule above), the PRD entry if applicable, and the affected items exactly as the script reported them.
7. Report: the contradiction verdict, the affected items per stage (verbatim from the script), and that a Change Request quote is needed next (never produce a price — that's `proposal-agent`'s job, and only after the human decides to proceed).

## Output Contract

Each run ends with the updated `state/change-requests-state.json` on disk and a chat report: contradiction verdict (with the exact PRD out-of-scope quote when applicable), priority-change verdict (`from`/`to` when applicable), the affected items per pipeline stage exactly as `find-affected.sh` reported them, and the new `CR-##` id. This skill never edits any other `*-state.json` (a priority change is reported, never applied here), never invokes another skill automatically, and never states or implies that the change is approved.

## References

- `../requirements-agent/SKILL.md` — the `prd_out_of_scope` contradiction pattern this skill reuses for change requests arriving after approval.
- `../orchestrator-agent/SKILL.md` — the script-does-mechanics / skill-relays-verbatim pattern this skill follows.
- `../../../ingenieria_requerimientos_agentica.md` — section 18 (Control de versiones y análisis de impacto) defines this skill's scope and worked example.
- `scripts/find-affected.sh` — the deterministic transitive reference traversal this skill wraps; propagates only a record's own declared id, never co-referenced siblings, to avoid false-positive blast radius.
- `assets/change-requests-state.schema.json` — state file shape.
