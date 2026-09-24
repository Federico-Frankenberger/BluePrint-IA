---
name: orchestrator-agent
description: "Trigger: orchestrator agent, orquestador, qué sigue, próximo paso del pipeline, estado del pipeline. Deterministically reports which of the 7 pipeline state files exist, what's missing, and flags stages whose upstream changed more recently than they did -- never reasons about it itself."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.1"
---

## Activation Contract

Load when the user runs `/orchestrator-agent`, asks what to run next in the pipeline, or asks for the current pipeline state.

## Hard Rules

- Never reason about sequencing or staleness yourself. Run `scripts/check-pipeline-state.sh` and relay its exact output -- this skill exists specifically so pipeline control is deterministic, not an LLM judgment call (see document section 12).
- Never write, modify, or delete any `*-state.json` file. This skill only reads and reports.
- Never invoke another skill automatically. Report the recommended next step; the user decides when to run it.

## Decision Gates

| Situation | Action |
|---|---|
| Script reports a missing stage | Relay "Próximo paso: ejecutar `<skill>`" verbatim. |
| Script reports all 7 present, no staleness | Relay "Pipeline completo" verbatim. |
| Script reports one or more stages "potentially stale" | Relay the staleness note verbatim; do not attempt to resolve it or guess which fields changed. |
| Script reports `Definition of Ready: FAILED` | Relay it verbatim; tell the user to run `/definition-of-ready-agent` for the itemized detail — this skill never expands the reasons itself, that's `definition-of-ready-agent`'s report. |
| Script reports `Definition of Ready: LEGACY` | Relay it verbatim; tell the user the run is frozen (not exempt) and to run `/definition-of-ready-agent` for the motivo/accionable detail. Never treat `LEGACY` as equivalent to `PASSED` — it still blocks `spec-package-agent`. |
| Script exits with an error | Relay the raw error; do not fall back to manually inspecting files and reasoning about state yourself. |

## Execution Steps

1. Run `bash .claude/skills/orchestrator-agent/scripts/check-pipeline-state.sh` from the project root via the Bash tool.
2. Relay its stdout verbatim as the report -- no paraphrasing of the table, no added interpretation of what "stale" means beyond what the script already states.
3. Apply the matching Decision Gate row.

## Output Contract

Each run ends with the script's plain-text table (stage | status | note), its closing line (next step or "Pipeline completo"), the staleness caveat when applicable, and the Definition of Ready verdict line, all relayed verbatim. This skill never edits any state file.

## References

- `../../../ingenieria_requerimientos_agentica.md` -- section 12 (Orquestador) defines this skill's scope and its explicit non-goal: it does not replace the Impact Analysis Agent (section 18), which reasons about *what* is affected by a change, not just *that* something might be stale.
- `../definition-of-ready-agent/SKILL.md` -- this skill's status check shells out to that skill's deterministic script; the full itemized failure detail lives there, not here.
- `scripts/check-pipeline-state.sh` -- the deterministic logic this skill wraps; the skill itself adds no judgment on top of it.
