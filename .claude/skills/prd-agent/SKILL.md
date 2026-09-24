---
name: prd-agent
description: "Trigger: prd agent, generar prd, product requirement document, in-scope out-of-scope, iniciar prd. Synthesizes confirmed state/discovery-state.json (and, by reference, requirements/user-stories/estimation state) into the full 30-section PRD from the manual, never promoting a pending_clarification item into scope silently and never duplicating a fact another skill already owns."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.4"
---

## Activation Contract

Load when the user runs `/prd-agent`, asks to synthesize/generate the PRD, define in-scope/out-of-scope, or asks to review `source/prd.md` / `state/prd-state.json` for this project.

## Design principle: referenced, not self-contained

`state/prd-state.json` is not a copy of the whole project. Every fact has exactly one source of truth. A section of the manual's PRD structure (`Manual-de-Analisis-de-Requerimientos.md` §24.2) is handled one of three ways — see the full 30-row mapping in `Plan-de-Mejora-Pipeline.md` (Etapa 5 / punto 7):

1. **PRD-owned field** — nothing else captures this; it's first-class in `assets/prd-state.schema.json` (`executive_summary`, `problem_statement`, `context`, `vision`, `objectives`, `non_goals`, `personas`, `in_scope`, `out_of_scope`, `constraints`, `mvp_scope`, `success_criteria`, `changelog`, `open_questions`).
2. **Reference** — another skill already owns this fact. Store only an id / file+field pointer under `references.*`, never the text itself. `source/prd.md` resolves the reference to readable prose at render time by reading the referenced file live.
3. **Not in PRD scope** — documented under `not_in_prd_scope` with the reason (today: only the glossary, §24.2.28, reserved for `spec-package/product/glossary.md` until some skill actually captures glossary terms).

Never write into a PRD-owned field something that belongs to a reference (that's the duplication this design exists to prevent), and never invent content to fill a reference that has nothing confirmed upstream — leave `ids: []` / the field empty and add a `note` explaining the gap, plus an `open_questions` entry if nothing already covers it.

## Hard Rules

- Never move a business rule or process whose Discovery `status` is `pending_clarification` into "In-Scope" or "Out-of-Scope". It stays in this skill's own `open_questions` until Discovery resolves it — silence is not a decision.
- Every "In-Scope" item traces to a confirmed `RN-##` rule or a named process from `state/discovery-state.json`. Never invent scope beyond what Discovery actually confirmed.
- Every persona traces to a `stakeholder` entry in `state/discovery-state.json`. Never invent a persona Discovery never mentioned. The enrichment fields (`context`, `needs`, `technical_level`) stay `null` unless the client/founder actually stated them — never inferred from the role name alone.
- `non_goals` and `constraints` each need an explicit source citation (a rule, a process, or a stakeholder statement). Never derive either from silence or from assuming "probably not in scope" — that guess belongs in `open_questions`, not in `non_goals`.
- `mvp_scope` entries MUST already exist verbatim in `in_scope`. Never add an item to `mvp_scope` that isn't already a confirmed in-scope item — this field only marks a subset, it never introduces new scope.
- Every `references.*` entry either has content (`ids` populated, or the referenced file/field genuinely has data) or an explicit `note` explaining why it's empty. Never leave a reference silently empty with no note — same "never skip in silence" principle as the rest of the pipeline.
- §25.1 rule — never let a technical implementation decision leak into a PRD-owned field or a rendered section. If the source material (a business rule, a stakeholder quote) is phrased as a technical solution ("usar PostgreSQL", "cachear la consulta 5 minutos", "la tabla `pedidos` con un campo `estado` enum"), rephrase it at the business-requirement level before writing it (see the manual's transformation examples, §25.1) — unless it is a genuine externally-imposed constraint (the client mandates a specific technology/vendor), in which case it belongs verbatim under `constraints` with its source, never under a functional/data section pretending to be a requirement.
- Read `engagement_type` from `state/discovery-state.json` and carry it into `state/prd-state.json` — Discovery is now the source of truth for the mode, this skill does not ask independently. Fallback only: if an old `state/discovery-state.json` predates this field and has it unset, ask the user once which mode applies, persist the answer in `state/prd-state.json`, and note in the report that Discovery is missing the field (a gap in that upstream file, not something to silently patch there).
- Persist state after every run. Read the existing `state/prd-state.json` first; add or update by source, never duplicate or overwrite from scratch. Regenerate `source/prd.md` in full each run (it's a document, not an incremental log). Append one `changelog` entry per run only when something material actually changed (a new section populated, a scope item added) — a re-run with no new upstream data adds no changelog entry.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/discovery-state.json` in project root | Stop. Tell the user to run `/discovery-agent` first. |
| Discovery has zero confirmed rules/processes | Stop. Report Discovery isn't ready yet — nothing to synthesize. |
| `state/discovery-state.json` has `engagement_type` set | Copy it into `state/prd-state.json` without asking. |
| `state/discovery-state.json` predates this field (unset) | Ask the user once which mode applies, persist to `state/prd-state.json`, note the upstream gap in the report. |
| Confirmed rule or process not yet reflected in scope | Add to "In-Scope", with its source. |
| Rule/process `status: pending_clarification` | Do not place in scope or out-of-scope; add/keep in this skill's `open_questions` as `{id, question, item_ref}` (`item_ref` = the rule/process). |
| Stakeholder with no mapped persona | Draft one persona per stakeholder, with its source; enrichment fields stay `null` unless actually stated. |
| A `references.*` entry has nothing to cite (its pointed-to field/file is empty or, for `data_entities`/`integrations`/`security`/`reports`/`notifications`, `state/discovery-state.json`'s `data_points`/`integrations`/`security_items`/`reports`/`notifications` has zero `status: confirmed` entries) | Write a `note` explaining the gap, and add a matching `open_questions` entry if one doesn't already exist for that topic. Never invent content to fill it. |
| Source material for a referenced or PRD-owned section reads as a technical implementation decision (§25.1) | Rephrase at business-requirement level before writing; if it's a stakeholder-imposed constraint, record it under `constraints` instead, never as a functional/data requirement. |
| A candidate `mvp_scope` item is not already in `in_scope` | Do not add it to `mvp_scope`. Add the underlying item to `in_scope` first (with its own source), only then to `mvp_scope`. |

## Execution Steps

1. Load `state/discovery-state.json` from the project root (apply the missing-file / not-ready Decision Gates if applicable).
2. Load or initialize `state/prd-state.json` (schema in `assets/prd-state.schema.json`). Copy `engagement_type` from `state/discovery-state.json`; only ask if the upstream file itself lacks it (pre-dates this field).
3. Draft the PRD-owned narrative fields — `executive_summary`, `problem_statement`, `context`, `vision`, `objectives`, `non_goals` — framed around an external client's need in `client` mode, or the founder's own product hypothesis in `own_product` mode. Each of `problem_statement`/`context`/`non_goals` traces back to discovery content (business rules, processes, stakeholder statements); never fabricate context discovery never surfaced.
4. Derive one persona per confirmed `stakeholder`, with its source; fill `context`/`needs`/`technical_level` only when the client/founder actually said something on that point, else leave `null`.
5. Build "In-Scope" from confirmed rules/processes; keep anything `pending_clarification` out of both scope lists and in `open_questions` (as `{id, question, item_ref}`) instead. Derive `mvp_scope` as a subset of `in_scope` only if the client/founder explicitly distinguished an MVP; otherwise leave it empty (not "everything is MVP" by default).
6. Draft "Criterios de éxito" from the confirmed rules and stated objectives — never invent a metric Discovery never implied.
7. Populate `constraints` from any explicitly stated external limit (budget, timeline, mandated technology, regulation) — never a design choice the team itself would make.
8. Resolve `references` — for each key in `assets/prd-state.schema.json`'s `references` block, confirm the pointed-to `file`+`field` exists and has at least one matching entry (every reference, including `data_entities`/`integrations`/`security`/`reports`/`notifications`, is now a direct `file`+`field` pointer — as of `discovery-state.schema.json` `1.3`, those five point 1:1 at Discovery's own `data_points`/`integrations`/`security_items`/`reports`/`notifications` arrays instead of being assembled by judgment from `business_rules`/RF ids). Write a `note` wherever the pointed-to field is empty or has nothing `confirmed` yet.
9. Add/update `changelog` with today's date if this run changed the document materially.
10. Write the full `source/prd.md` (see Output Contract for its structure) and update `state/prd-state.json`.
11. Report: which PRD-owned fields were drafted/updated, personas derived (with source), in-scope/MVP items (with source), which references resolved vs. which are gaps (with the matching `open_questions`), and the traceability link back to Discovery/Requirements/User Stories/Estimation.

## Output Contract

Each run ends with `source/prd.md` and `state/prd-state.json` (traceability back to Discovery and, by reference, to Requirements/User Stories/Estimation) on disk, plus a short summary in chat of scope / personas / open items / reference gaps. On request, output the full file as the handoff artifact for the next pipeline stage (Requirements) — `requirements-agent` reads `state/prd-state.json` and gates any candidate requirement against its `out_of_scope`.

`source/prd.md` renders the **full 30-section structure of the manual (§24.2)**, in that order, one heading per section:

1. Resumen ejecutivo (`executive_summary`)
2. Problema (`problem_statement`)
3. Contexto (`context`)
4. Objetivos (`objectives`)
5. No objetivos (`non_goals`)
6. Stakeholders (resolved from `references.stakeholders`)
7. Usuarios (derived from `personas` — the distinct actor/role list, no separate field)
8. Personas / perfiles (`personas`, full enrichment when present)
9. Alcance (`in_scope` / `out_of_scope`)
10. Funcionalidades (resolved from `references.functional_requirements`, grouped by process/module)
11. Procesos (resolved from `references.processes` — AS-IS summarized, TO-BE proposed)
12. Reglas de negocio (resolved from `references.business_rules`)
13. Datos (resolved from `references.data_entities`)
14. Integraciones (resolved from `references.integrations`)
15. Requisitos no funcionales (resolved from `references.non_functional_requirements`)
16. Seguridad (resolved from `references.security`)
17. Reportes (resolved from `references.reports`)
18. Notificaciones (resolved from `references.notifications`)
19. Restricciones (`constraints`)
20. Dependencias (resolved from `references.dependencies`)
21. Riesgos (resolved from `references.risks`)
22. Supuestos (resolved from `references.assumptions`)
23. Priorización (resolved from `references.prioritization` — a MoSCoW summary table built from RF/RNF/HU `priority` fields)
24. Métricas de éxito (`success_criteria`)
25. MVP (`mvp_scope`)
26. Fuera de alcance (`out_of_scope` — same data as §9, operational framing)
27. Preguntas abiertas (`open_questions`)
28. Glosario del dominio — **not rendered here**; the section header appears with a one-line pointer to `spec-package/product/glossary.md` and the `not_in_prd_scope.glossary` reason, per the design principle above.
29. Historial de cambios del documento (`changelog`)
30. Referencias y trazabilidad — built at render time from every `source`/`ids`/reference already used across the document above; never a separately stored field.

Any section whose backing field/reference is empty renders explicitly as **"Sin información relevada todavía — ver Preguntas abiertas"** (with the matching `open_questions` entry), never silently omitted and never invented.

## References

- `../discovery-agent/SKILL.md` — upstream stage; the `state/discovery-state.json` contract this skill reads directly and references. `schema_version: "1.3"` adds `data_points`/`integrations`/`security_items`/`reports`/`notifications`, which `references.data_entities`/`.integrations`/`.security`/`.reports`/`.notifications` now point at 1:1 instead of citing `business_rules`/RF ids by judgment.
- `../requirements-agent/SKILL.md`, `../user-stories-agent/SKILL.md`, `../estimation-agent/SKILL.md` — downstream/sibling skills whose state files this skill's `references` block points into for Funcionalidades, RNF, Priorización, Dependencias, Riesgos, Supuestos — never copied, always resolved live.
- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline; PRD design in section 3, `engagement_type` mode in section 2.
- `../../../Manual-de-Analisis-de-Requerimientos.md` — sección 24.2 (estructura completa del PRD, la fuente de las 30 secciones) y sección 25.1 (qué no debe pasar prematuramente al PRD).
- `../../../Plan-de-Mejora-Pipeline.md` — Etapa 5 / punto 7: la tabla completa de mapeo sección→dueño que motivó este diseño.
- `assets/prd-state.schema.json` — state file shape.
