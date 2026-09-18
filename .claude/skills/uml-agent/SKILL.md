---
name: uml-agent
description: "Trigger: uml agent, generar uml, diagrama de casos de uso, diagrama de estados, iniciar uml. Generates traceable Mermaid diagrams from confirmed requirements/stories, blocking diagram types whose data isn't confirmed instead of fabricating it."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.1"
---

## Activation Contract

Load when the user runs `/uml-agent`, asks to generate or update UML/diagrams, or asks to review `state/uml-state.json` for this project.

## Hard Rules

- Every diagram element (actor, state, transition, class, relationship) carries an explicit source id (`RF-##`, `HU-##`, or `RN-##`). Never draw an element with no source.
- Only generate a diagram **type** when the confirmed data actually supports it. A class/ERD diagram needs confirmed attributes and cardinalities; a sequence/activity diagram needs a confirmed step order. Missing data means `blocked`, never a guessed attribute or arrow.
- Diagrams are dynamic: when upstream state changes, update only the affected diagram file in place. Never regenerate every diagram on every run.
- Diagrams are plain-text Mermaid (`.mmd`) under `diagrams/` - diffable in git, no external renderer required to review a change.
- Persist `state/uml-state.json` after every run: which diagram file maps to which source ids, and what's `blocked`. Read the existing file first; never overwrite from scratch.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/requirements-state.json` or `state/user-stories-state.json` | Stop. Tell the user which upstream stage (`/requirements-agent` or `/user-stories-agent`) to run first. |
| Actors (from `state/discovery-state.json`) + at least one `HU-##` exist | Generate/update `diagrams/use-case.mmd`, one interaction per story, source-tagged. |
| A set of confirmed rules describes 2+ states/transitions for one entity | Generate/update `diagrams/<entity>-state.mmd`, each transition traced to its `RN-##`/`RF-##`. |
| Class/ERD/sequence/activity diagram whose required data (attributes, cardinalities, step order) isn't confirmed | Add to `blocked` with `status: "blocked"` and exactly what's missing. Do not fabricate it. |
| Upstream state changed since last run | Update only the diagram file(s) whose source ids changed; leave the rest untouched. |

## Execution Steps

1. Load `state/discovery-state.json`, `state/requirements-state.json`, `state/user-stories-state.json` (apply the missing-file gate if either upstream file is absent).
2. Load or initialize `state/uml-state.json` (schema in `assets/uml-state.schema.json`).
3. Build/update the use-case diagram from actors + `HU-##` stories.
4. Detect any entity whose confirmed rules describe a multi-state lifecycle; build/update its state diagram.
5. For every other classic diagram type, check whether its required data is confirmed; if not, add it to `blocked` with the specific gap.
6. Write each diagram to `diagrams/<name>.mmd` and update `state/uml-state.json` with its source ids.
7. Report: diagrams written/updated (with sources), and what's blocked and why.

## Output Contract

Each run ends with updated `.mmd` files under `diagrams/`, an updated `state/uml-state.json` on disk, a short summary of what changed and its sources, and the `blocked` list when non-empty.

## References

- `../user-stories-agent/SKILL.md` — upstream stage; the `state/user-stories-state.json` contract this skill reads.
- `../requirements-agent/SKILL.md` — upstream `state/requirements-state.json` contract.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline this stage feeds into.
- `assets/uml-state.schema.json` — state file shape.
