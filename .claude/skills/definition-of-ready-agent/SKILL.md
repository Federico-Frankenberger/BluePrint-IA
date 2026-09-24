---
name: definition-of-ready-agent
description: "Trigger: definition of ready, DoR, está listo, chequear listo para SDD, verificar antes de armar el spec package. Deterministically checks whether every confirmed user story meets Definition of Ready (priority assigned, acceptance criteria present including at least one exception-type AC, no unresolved open_questions, source requirement confirmed) plus full discovery coverage -- never a judgment call, and it blocks spec-package-agent when it fails."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.2"
---

## Activation Contract

Load when the user runs `/definition-of-ready-agent`, asks "¿está listo para SDD?" / "¿pasa Definition of Ready?", or when `spec-package-agent` is about to run (see its own Decision Gates — it calls this skill first).

## Hard Rules

- Never reason about readiness yourself. Run `scripts/check-definition-of-ready.sh` and relay its exact output — this skill exists specifically so the gate is deterministic reformatting of already-persisted state, not an LLM judgment call (same precedent as `orchestrator-agent` and `spec-package-agent`).
- Never write, modify, or delete any `state/*.json` file. This skill only reads and reports.
- **The gate is a hard block, not a warning.** A `FAILED` verdict means `spec-package-agent` must refuse to assemble the Spec Package until every listed reason is resolved — never assemble a package with known-incomplete stories "for now."
- Every failure reason returned by the script already names the concrete next step (which skill to re-run, and for which item) — relay it verbatim, never paraphrase it into something vaguer like "faltan datos."
- **Every evaluated story needs at least one `type: "exception"` Acceptance Criteria, not just `happy_path` — OR a well-formed, explicit waiver.** `user-stories-agent`'s own Hard Rule already requires an exception AC whenever one is knowable — this check is what actually enforces that instead of trusting it silently. A story whose `acceptance_criteria` has entries but none of them `type: "exception"` fails with `"sin criterio de aceptación de excepción -- correr user-stories-agent de nuevo, historia HU-##"`, **unless** it carries a well-formed `no_exception_reason` object (`user-stories-state.schema.json`, schema 1.2+): `reason` and `stated_by` both non-empty. That is the only legitimate way to document "no exception is knowable, and a stakeholder confirmed it" instead of leaving it as silent absence — never inferred, never assumed on the gate's own initiative.
  - **A waiver is fail-closed, same as everything else in this gate.** A `no_exception_reason` object that's present but malformed (`reason` empty, `stated_by` missing or empty) does **not** fall back to the generic missing-AC message — it gets its own distinct message: `"no_exception_reason mal formado (falta reason y/o stated_by) -- correr user-stories-agent de nuevo, historia HU-##"`. A malformed waiver is never treated as equivalent to no waiver, and never silently passes.
  - **A waiver never leaks across stories.** Each story's own `no_exception_reason` (like its own `acceptance_criteria`) is read in isolation from that story's own blob — a waiver recorded on HU-04 can never satisfy HU-05's gate.
  - **Waived stories still pass, but are never hidden.** A story that passes via waiver is listed under "Historias listas" like any other, *and* separately under a dedicated "Historias con waiver de excepción" block in the report, naming the story, the `reason`, and `stated_by` verbatim — so a reviewer always sees which stories skipped the exception AC and why, instead of that fact disappearing into an ordinary pass.
- **Legacy is not a bypass.** A run can be frozen via `discovery-state.json`'s optional `legacy` object (see the schema and `Plan-de-Mejora-Pipeline.md` punto 11) — this only changes the *reported status* to `LEGACY` instead of the plain `FAILED` list; it never makes the gate pass and it never stops the gate from blocking `spec-package-agent`. Fail closed: a `legacy` object that's absent, partial, or malformed (`is_legacy` not literally `true`, or missing `reason`/`marked_at`) is treated as **not legacy** by the script — relay it as an ordinary `FAILED`, never assume legacy on the script's behalf.

## Decision Gates

| Situation | Action |
|---|---|
| `state/user-stories-state.json` doesn't exist | Relay the script's message; tell the user which skills to run first. |
| Script exits 0 (`VEREDICTO: PASSED`) | Relay the pass report; `spec-package-agent` may proceed. |
| Script exits 2 (`VEREDICTO: FAILED`) | Relay the fail report verbatim, including every per-story reason and the discovery-coverage detail when present; `spec-package-agent` must not assemble the package. |
| Script exits 3 (`VEREDICTO: LEGACY`) | Relay the `LEGACY` block verbatim (motivo, marcada el, predates_schema_version, accionable) plus the rest of the report; `spec-package-agent` must still not assemble the package — legacy is frozen, not exempt. Tell the user the only way out is reopening via `discovery-agent` (which removes the `legacy` marker once coverage/priority/AC are completed). |
| Script exits with any other error | Relay the raw error; do not fall back to manually reading state files and judging readiness yourself. |

## Execution Steps

1. Run `bash .claude/skills/definition-of-ready-agent/scripts/check-definition-of-ready.sh .` from the project root via the Bash tool.
2. Relay its stdout verbatim as the report — no paraphrasing, no softening of a `FAILED` verdict.
3. Apply the matching Decision Gate row.

## Output Contract

Each run reports: how many stories were evaluated, discovery coverage status (12/12 obligatorias + 0 open_questions, or the specific gap), the list of stories that passed, a separate "Historias con waiver de excepción" block for any story that passed via `no_exception_reason` (naming the story, `reason`, and `stated_by`), and — when any fail — the list of stories that didn't with the exact, actionable reason for each (never just the field name). Ends with `VEREDICTO: PASSED`, `VEREDICTO: FAILED`, or `VEREDICTO: LEGACY`. When legacy, an extra block right after the header names the motivo, marcada el, predates_schema_version and the actionable next step (reopen via `discovery-agent`). This report is what `spec-package-agent` and `orchestrator-agent` both key off of — `orchestrator-agent`'s "Definition of Ready:" row shows `LEGACY` automatically, since it just relays this script's `VEREDICTO:` line.

## References

- `../../../ingenieria_requerimientos_agentica.md` — section 17 (ciclo de vida) defines the shared state vocabulary this gate checks; section 20 tracks this skill's implementation status.
- `../../../Manual-de-Analisis-de-Requerimientos.md`, sección 28 — Definition of Ready as a non-negotiable gate before a technical design phase; this skill is that gate, enforced inside the pipeline instead of left to whatever SDD engine receives the Spec Package.
- `../spec-package-agent/SKILL.md` — downstream consumer; refuses to assemble when this gate fails.
- `../orchestrator-agent/SKILL.md` — sibling cross-cutting skill; surfaces this gate's status in "estado del pipeline."
- `../requirements-agent/SKILL.md`, `../user-stories-agent/SKILL.md` — the skills a failure reason typically points back to.
- `../user-stories-agent/assets/user-stories-state.schema.json` — the `no_exception_reason` waiver shape this gate accepts (schema 1.2+).
- `scripts/check-definition-of-ready.sh` — the deterministic logic this skill wraps; the skill itself adds no judgment on top of it.
