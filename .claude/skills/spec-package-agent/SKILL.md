---
name: spec-package-agent
description: "Trigger: spec package agent, armar spec package, ensamblar spec package, generar manifest. Deterministically assembles the confirmed output of all 7 pipeline skills into the section-16 folder tree plus a manifest.json indexing each skill's schema -- never synthesizes or edits content itself."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.0"
---

## Activation Contract

Load when the user runs `/spec-package-agent`, asks to assemble/build the Spec Package, or asks for `manifest.json` / the `spec-package/` folder for this project.

## Hard Rules

- Never reason about which items belong in the Spec Package yourself. Run `scripts/assemble-spec-package.sh` and relay its exact output -- this skill exists specifically so assembly is deterministic reformatting of already-validated state, not an LLM judgment call (see document section 16, and the Orquestador's determinism principle in section 12).
- Never write, modify, or delete any `*-state.json`, `prd.md`, `propuesta.md`, or `diagrams/*.mmd` source file. This skill only reads sources and writes under `spec-package/`.
- Never invoke another skill automatically. If a source file is missing, relay the script's placeholder note and tell the user which upstream skill to run first.
- Never silently drop a `rejected`/`blocked`/`pending_clarification`/`skipped` item from the summary the script prints -- relay the exclusion summary verbatim, it's the transparency mechanism for this skill.

## Decision Gates

| Situation | Action |
|---|---|
| Script completes normally | Relay the "Spec Package ensamblado en..." line and the full exclusion summary verbatim. |
| A source file is missing (e.g. no `state/estimation-state.json` yet) | Relay the placeholder note the script wrote into that output file; tell the user which skill produces it. |
| Script exits with an error | Relay the raw error; do not fall back to manually reading state files and assembling content yourself. |

## Execution Steps

1. Run `bash .claude/skills/spec-package-agent/scripts/assemble-spec-package.sh .` from the project root via the Bash tool.
2. Relay its stdout verbatim as the report -- no paraphrasing of the exclusion summary, no added interpretation.
3. Apply the matching Decision Gate row.

## Output Contract

Each run rebuilds `spec-package/` in full (idempotent -- safe to re-run at any time, always reflects current state) with `manifest.json` at its root plus the `product/`, `requirements/`, `user-stories/`, `models/`, `acceptance/`, `estimation/`, `proposal/` subfolders from document section 16. `architecture/` is deliberately omitted -- no agent produces ADRs yet, and this skill never fabricates placeholder content for a folder nothing backs. The report always includes the exclusion summary (confirmed vs. rejected/blocked/skipped counts per file), so nothing is lost silently.

## References

- `../../../ingenieria_requerimientos_agentica.md` -- section 16 (Spec Package) defines the target folder shape; section 12 (Orquestador) is the precedent for this skill's determinism requirement; section 13 (Harness) is the future consumer of `manifest.json`.
- `scripts/assemble-spec-package.sh` -- the deterministic logic this skill wraps; the skill itself adds no judgment on top of it.
- `../orchestrator-agent/SKILL.md` -- sibling cross-cutting skill with the same "wrap a deterministic script, never second-guess it" shape.
