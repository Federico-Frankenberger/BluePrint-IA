---
name: user-stories-agent
description: "Trigger: user stories agent, generar historias de usuario, HU, iniciar user stories. Turns confirmed RF entries into traceable Gherkin user stories, flagging unstated edge cases instead of inventing them."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.1"
---

## Activation Contract

Load when the user runs `/user-stories-agent`, asks to generate user stories, or asks to review `state/user-stories-state.json` for this project.

## Hard Rules

- Every story carries an explicit `source` (an `RF-##` id). Never write an orphan story.
- `RNF` entries never become stories - skip them and record each in `skipped` with reason `"non-functional"`.
- Every story needs an actor. Infer it from `state/discovery-state.json`'s `stakeholders`; if none fits, ask rather than guess.
- If a Given/When/Then needs an edge case the RF text doesn't answer (a failure path, a missing-data case), never invent the behavior - add it to that story's `open_questions` as `{id, question, item_ref}` (`item_ref` = the story's own id) instead of fabricating the step.
- Persist state after every run. Read the existing file first; add or update by `source`, never duplicate or overwrite from scratch.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/requirements-state.json` in project root | Stop. Tell the user to run `/requirements-agent` first. |
| `RF` entry not yet mapped to a story | Generate one `HU-##`: actor, action, benefit, Gherkin criteria, `source`. |
| `RNF` entry | Skip; record in `skipped` with reason `"non-functional"`. |
| Acceptance criteria need an unstated edge case | Write the criteria that ARE knowable; add the edge case as one `{id, question, item_ref}` entry in that story's `open_questions`. |
| `state/requirements-state.json` changed since last run | Add only the new stories; keep existing `HU-##` ids stable. |

## Execution Steps

1. Load `state/requirements-state.json` (apply the missing-file gate if absent) and `state/discovery-state.json` for actor names.
2. Load or initialize `state/user-stories-state.json` (schema in `assets/user-stories-state.schema.json`).
3. For each unmapped `RF`, pick the actor, draft "Como `<actor>` quiero `<acción>` para `<beneficio>`", and derive Given/When/Then from the RF text and its upstream rule/process.
4. Where an edge case is unstated, add it to that story's `open_questions` instead of guessing.
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
