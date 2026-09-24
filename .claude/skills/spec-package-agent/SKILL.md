---
name: spec-package-agent
description: "Trigger: spec package agent, armar spec package, ensamblar spec package, generar manifest. Deterministically assembles the confirmed output of all 7 pipeline skills into the section-16 folder tree plus a manifest.json indexing each skill's schema -- never synthesizes or edits content itself."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.2"
---

## Activation Contract

Load when the user runs `/spec-package-agent`, asks to assemble/build the Spec Package, or asks for `manifest.json` / the `spec-package/` folder for this project.

## Hard Rules

- **Definition of Ready is a hard block.** The script runs `definition-of-ready-agent`'s gate before touching the output directory. If it fails (`FAILED`) or the run is `LEGACY`, the script exits without assembling anything — relay its output verbatim and tell the user to resolve it (or, for `LEGACY`, that reopening via `discovery-agent` is the only way out) and re-run. Never assemble "the parts that are ready" as a partial package; the gate is pass/fail/legacy for the whole run, and only `PASSED` lets assembly proceed.
- Never reason about which items belong in the Spec Package yourself. Run `scripts/assemble-spec-package.sh` and relay its exact output -- this skill exists specifically so assembly is deterministic reformatting of already-validated state, not an LLM judgment call (see document section 16, and the Orquestador's determinism principle in section 12).
- Never write, modify, or delete any `*-state.json`, `prd.md`, `propuesta.md`, or `diagrams/*.mmd` source file. This skill only reads sources and writes under `spec-package/`.
- Never invoke another skill automatically. If a source file is missing, relay the script's placeholder note and tell the user which upstream skill to run first.
- Never silently drop a `rejected`/`blocked`/`pending_clarification`/`skipped` item from the summary the script prints -- relay the exclusion summary verbatim, it's the transparency mechanism for this skill.

## Decision Gates

| Situation | Action |
|---|---|
| Script completes normally | Relay the "Spec Package ensamblado en..." line and the full exclusion summary verbatim. |
| A source file is missing (e.g. no `state/estimation-state.json` yet) | Relay the placeholder note the script wrote into that output file; tell the user which skill produces it. |
| Definition of Ready fails (script exits 1 with "Spec Package NO ensamblado") | Relay the full DoR failure output verbatim — every per-story reason and the discovery-coverage detail. Do not assemble anything, do not suggest a partial package. |
| Definition of Ready reports the run is `LEGACY` (script exits 1, header says "la corrida esta marcada LEGACY") | Relay the full LEGACY output verbatim (motivo, marcada el, accionable). Do not assemble anything and do not treat `LEGACY` as a pass — it is frozen, not exempt; the only way out is reopening via `discovery-agent`. |
| Script exits with an error | Relay the raw error; do not fall back to manually reading state files and assembling content yourself. |

## Execution Steps

1. Run `bash .claude/skills/spec-package-agent/scripts/assemble-spec-package.sh .` from the project root via the Bash tool.
2. Relay its stdout verbatim as the report -- no paraphrasing of the exclusion summary, no added interpretation.
3. Apply the matching Decision Gate row.

## Output Contract

Each successful run rebuilds `spec-package/` in full (idempotent -- safe to re-run at any time, always reflects current state) with `manifest.json` at its root (`contract_version: "1.1"`, `dor_status: "passed"`) plus the `product/`, `requirements/`, `user-stories/`, `models/`, `acceptance/`, `estimation/`, `proposal/` subfolders from document section 16 -- now including `product/as-is-to-be.md`, `product/coverage-report.md`, `product/glossary.md` (reserved, unpopulated until a skill captures it), `acceptance/definition-of-ready.md`, and `acceptance/open-questions.md`. Priority shows inline on every RF/RNF/HU; `requirements/business-rules.md` shows `stated_by`; `estimation/estimate.md` splits Riesgos/Supuestos/Dependencias. `architecture/` is deliberately omitted -- no agent produces ADRs yet, and this skill never fabricates placeholder content for a folder nothing backs. The report always includes the exclusion summary (confirmed vs. rejected/blocked/skipped counts per file), so nothing is lost silently. A run that fails Definition of Ready produces no output directory at all -- nothing partial, nothing stale left behind.

## References

- `../../../ingenieria_requerimientos_agentica.md` -- section 16 (Spec Package) defines the target folder shape; section 12 (Orquestador) is the precedent for this skill's determinism requirement; section 13 (Harness) is the future consumer of `manifest.json`.
- `../definition-of-ready-agent/SKILL.md` -- the hard gate this skill's script runs before assembling anything.
- `scripts/assemble-spec-package.sh` -- the deterministic logic this skill wraps; the skill itself adds no judgment on top of it.
- `../orchestrator-agent/SKILL.md` -- sibling cross-cutting skill with the same "wrap a deterministic script, never second-guess it" shape.
