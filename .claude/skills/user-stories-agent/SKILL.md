---
name: user-stories-agent
description: "Trigger: user stories agent, generar historias de usuario, HU, iniciar user stories. Turns confirmed RF entries into traceable Gherkin user stories, flagging unstated edge cases instead of inventing them."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.3"
---

## Activation Contract

Load when the user runs `/user-stories-agent`, asks to generate user stories, or asks to review `state/user-stories-state.json` for this project.

## Hard Rules

- Every story carries an explicit `source` (an `RF-##` id). Never write an orphan story.
- `RNF` entries never become stories - skip them and record each in `skipped` with reason `"non-functional"`.
- Every story needs an actor. Infer it from `state/discovery-state.json`'s `stakeholders`; if none fits, ask rather than guess.
- If a Given/When/Then needs an edge case the RF text doesn't answer (a failure path, a missing-data case), never invent the behavior - add it to that story's `open_questions` as `{id, question, item_ref}` (`item_ref` = the story's own id) instead of fabricating the step.
- **`priority` is inherited, never re-asked.** Copy the source `RF-##`'s `priority` (and leave `null` if the source is `null`) — this skill never assigns or re-derives priority itself, it only propagates what `requirements-agent` already resolved.
- **Every story needs at least one `exception` Acceptance Criteria when an exception is knowable, not just the `happy_path`.** An exception is knowable when it's implied by the RF's source rule (a validation, a restriction, a state transition that blocks something) or by a related `business_rule`/`open_question` already in `discovery-state.json`. Write the `happy_path` AC first, then check for a knowable exception and write it as a second AC entry with `type: "exception"`. Only when no exception is knowable from what's already confirmed does it stay as a single `happy_path` AC — never fabricate an exception that isn't grounded in something already relevado, and never skip a knowable one just to save a step.
- **Never invent an exception AC just to satisfy the Definition of Ready gate.** If a story genuinely has no knowable exception case (a trivial CRUD with no business rule behind it), that absence needs to be *explicit*, never silent and never faked. Two legitimate paths, and only these two:
  1. **Unclear whether an exception applies** → add it to the story's `open_questions` as `{id, question, item_ref}` (same as any other unstated edge case) and ask before closing the story.
  2. **Confirmed that no exception applies** → record `no_exception_reason: {reason, stated_by, source_turn}` on the story, and *only* when a stakeholder actually confirmed it (`stated_by` is required — never write this from your own inference). `reason` and `stated_by` must both be non-empty the moment this object exists; a waiver with either one missing or blank is worse than no waiver at all, because `check-definition-of-ready.sh` fails it closed with a distinct "malformed waiver" message instead of the ordinary "missing exception AC" one.
  Never combine a fabricated `type: "exception"` AC with a `no_exception_reason` on the same story, and never write a `no_exception_reason` with an empty `reason` "just to have something there" — an empty or unconfirmed waiver is exactly as invalid as inventing the exception itself.
- Persist state after every run. Read the existing file first; add or update by `source`, never duplicate or overwrite from scratch.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/requirements-state.json` in project root | Stop. Tell the user to run `/requirements-agent` first. |
| `RF` entry not yet mapped to a story | Generate one `HU-##`: actor, action, benefit, `priority` (copiado del RF), Gherkin criteria, `source`. |
| `RNF` entry | Skip; record in `skipped` with reason `"non-functional"`. |
| A knowable exception exists (regla de origen o `business_rule`/`open_question` relacionada) | Escribir un AC adicional `type: "exception"` para ese caso, no solo el `happy_path`. |
| Acceptance criteria need an unstated edge case that no confirmed data answers | Write the criteria that ARE knowable; add the edge case as one `{id, question, item_ref}` entry in that story's `open_questions` instead of a fabricated `exception` AC. |
| No exception is knowable AND it's unclear whether one even applies | Add it to `open_questions` (same shape as above) — never invent the AC, never write a waiver on a guess. |
| No exception applies AND a stakeholder explicitly confirmed that | Record `no_exception_reason: {reason, stated_by, source_turn}` on the story — `stated_by` required, never inferred. |
| `state/requirements-state.json` changed since last run | Add only the new stories; keep existing `HU-##` ids stable. |

## Execution Steps

1. Load `state/requirements-state.json` (apply the missing-file gate if absent) and `state/discovery-state.json` for actor names.
2. Load or initialize `state/user-stories-state.json` (schema in `assets/user-stories-state.schema.json`).
3. For each unmapped `RF`, pick the actor, draft "Como `<actor>` quiero `<acción>` para `<beneficio>`", copy its `priority`, and derive the `happy_path` Given/When/Then from the RF text and its upstream rule/process.
4. Check whether a knowable exception exists (source rule or related `business_rule`/`open_question`); if so, add a second AC entry `type: "exception"`. Where an edge case is unstated and not knowable from confirmed data, add it to that story's `open_questions` instead of guessing. Where no exception is knowable at all, either leave it as an `open_questions` entry (unclear) or, only if a stakeholder explicitly confirmed no exception applies, record `no_exception_reason` (confirmed) — never both, and never a `no_exception_reason` without a real `stated_by`.
5. Skip `RNF` entries into `skipped`.
6. Assign the next `HU-##` id; attach the `source` reference.
7. Write the full state back to `state/user-stories-state.json`.
8. Report: stories added (with source), any `open_questions`, and what was skipped and why.

## Output Contract

Each run ends with the updated `state/user-stories-state.json` on disk, a short summary of new `HU-##` entries with their source, any per-story `open_questions`, and the `skipped` list when non-empty. On request, output the full file as the handoff artifact for the next pipeline stage (UML/Modeling).

## References

- `../requirements-agent/SKILL.md` — upstream stage; the `state/requirements-state.json` contract this skill reads.
- `../discovery-agent/SKILL.md` — actor/stakeholder source.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline this stage feeds into.
- `assets/user-stories-state.schema.json` — state file shape.
