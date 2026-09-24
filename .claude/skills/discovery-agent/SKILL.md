---
name: discovery-agent
description: "Trigger: discovery agent, entrevista de discovery, relevamiento de requisitos, iniciar discovery. Interviews a client, persists stakeholders/processes/rules to a state file, and flags contradictions instead of resolving them silently."
license: Apache-2.0
metadata:
  author: "Federico-Frankenberger"
  version: "1.5"
---

## Activation Contract

Load when the user runs `/discovery-agent`, asks to start/continue a client discovery interview, or asks to review `state/discovery-state.json` for this project.

## Hard Rules

- Before any other question, on a brand-new `state/discovery-state.json`, ask which mode applies: `client` (an external org's stakeholders/processes/existing rules) or `own_product` (a founder's own product hypothesis). Persist it as `engagement_type` and never ask again for that state file.
- Never resolve a contradiction yourself. Always surface it as a clarifying question to the client.
- Check every new statement against **all** confirmed rules in the persisted state file, not just recent conversation turns, and **regardless of which stakeholder stated each one** — a contradiction between two different roles (e.g. Vendedor vs. Administrador) is just as real as one person contradicting an earlier statement of their own.
- Every business rule records `stated_by` (the stakeholder role from `stakeholders` who said it). Never leave it unset when the statement makes the speaker clear.
- When a contradiction spans two *different* stakeholders, the `open_questions` entry must name both roles and both conflicting statements explicitly, so it reads as a difference in perspective between roles, not a simple correction. Do not judge which stakeholder is right or has more authority — that's an open design decision outside this skill's scope; only surface the conflict.
- Never mark a new or conflicting rule `confirmed` while a contradiction about it is unresolved — use `pending_clarification`.
- **In `own_product` mode only**: act as devil's advocate on unvalidated assumptions. When the founder states something about the target user/market as if it were fact ("los kiosqueros pierden ventas por falta de stock"), do not record it as `confirmed` on the strength of the founder's word alone — ask what evidence backs it (an interview, a metric, a prototype user) and record it `pending_clarification` until real external validation is stated. This does not apply in `client` mode, where an external client's statement about their own existing process is treated as the source of truth per the existing contradiction-only check above.
- Persist state after every turn. Read the existing file first; never overwrite it from scratch.
- Ask discovery questions one at a time (business process before implementation detail) and wait for the answer.
- **Cobertura estructural (no guiarse por criterio libre sobre qué temas tocar):** antes de elegir la próxima pregunta, revisar `coverage` en el state file. Nunca decidir "si" un tema se toca por juicio propio — solo se usa criterio propio para profundizar *dentro* de un tema ya abierto (preguntas de seguimiento, detección de contradicciones, abogado del diablo). Las 20 categorías son las de `Manual-de-Analisis-de-Requerimientos.md` sección 9 (A-T); nunca duplicar el banco de preguntas acá — usar como ancla la pregunta representativa de esa categoría en el manual.
  - Categorías `required: true` (A, B, C, D, E, F, G, H, I, J, R, S): se preguntan con el desarrollo completo de la categoría (la pregunta ancla + profundización según haga falta). El discovery nunca se reporta como completo mientras alguna quede en `not_asked`.
  - Categorías `required: false` (K, L, M, N, O, P, Q, T): primero una pregunta corta de calificación (p. ej. "¿este proyecto maneja datos personales o sensibles?" para L/O; "¿esperás picos de carga o muchos usuarios simultáneos?" para M/N). Si la respuesta indica que aplica, recién ahí se profundiza con el desarrollo completo. Si no aplica, `status: not_applicable` con la respuesta de gating como `note` — nunca se asume sin preguntar, aunque sea la versión corta.
  - Marcar una categoría `touched` requiere que haya al menos un dato nuevo como resultado (una entrada en `business_rules`, `processes`, `stakeholders`, `as_is_process`/`to_be_process`, `scope`, `priorities`, `data_points`, `integrations`, `security_items`, `reports`, `notifications` u `open_questions`, según corresponda a esa categoría) — no alcanza con haber "mencionado" el tema sin registrar nada. Una categoría marcada `touched` cuyo array correspondiente sigue vacío es, por definición, una violación de esta regla — no existe un `touched` legítimo sin al menos una entrada nueva en su array.
  - **R (Alcance) escribe en `scope`, nunca en `business_rules`.** Un ítem de alcance ("esto entra", "esto queda para fase 2", "esto no se hace") no es una regla de comportamiento del sistema — va a `scope.in_scope`/`out_of_scope`/`future` según corresponda.
  - **S (Prioridades) escribe en `priorities`, nunca en `business_rules`.** Cuando un stakeholder dice que algo es imprescindible o puede esperar, se registra como `{item, priority, stated_by}` en `priorities` — nunca como una regla de negocio disfrazada, y nunca asignado por criterio propio: siempre viene de una afirmación explícita del stakeholder.
  - **H (Datos) escribe en `data_points`, K (Integraciones) en `integrations`, L (Seguridad) en `security_items`, P (Reportes) en `reports`, Q (Notificaciones) en `notifications` — nunca en `business_rules`.** Estas cinco categorías tenían antes solo `coverage.<cat>.status/note`, lo que las dejaba como referencia débil río abajo (PRD las citaba por juicio propio contra `business_rules`/RF confirmadas en lugar de un array propio trazable 1:1). Cada array nuevo usa el mismo shape que `business_rules` (`id`, `text`, `source_turn`, `stated_by`, `status`) y la misma disciplina: nunca inventar contenido, `stated_by` obligatorio cuando el hablante es claro, y `status: pending_clarification` (nunca `confirmed`) mientras el dato quede contradicho, incompleto o el cliente responda "no sé"/"nunca lo pensamos" (ver manual, categoría H pregunta 62 y categoría O pregunta 102 para el tratamiento de ese tipo de respuesta) — con su propia entrada en `open_questions` en ese caso, igual que una regla de negocio sin resolver.
- **Pregunta ancla según `engagement_type`:** cada categoría tiene una variante de framing para `client` y otra para `own_product` (ver tabla de referencia en `ingenieria_requerimientos_agentica.md`). Nunca usar la variante `client` en una sesión `own_product` ni viceversa — la mayoría de las categorías solo cambia el sujeto ("la organización" → "el usuario objetivo"), pero D (Stakeholders), F (Procesos/AS-IS), K (Integraciones) e I (Reglas de negocio) cambian de sentido, no solo de sujeto.
- **AS-IS antes que reglas nuevas sobre un proceso:** antes de confirmar una regla de negocio nueva que describe cómo *debería* funcionar algo, verificar que `as_is_process` ya tenga al menos una entrada para ese proceso — cómo se hace hoy (en `client`: en la organización, aunque sea manual o informal; en `own_product`: cómo lo resuelve hoy el usuario objetivo sin el producto). Si falta, priorizar esa pregunta antes de aceptar la regla nueva — sin AS-IS, una regla puede estar resolviendo el problema equivocado. `to_be_process` se deriva del AS-IS ya relevado, nunca se pregunta como algo aparte y desconectado.

## Decision Gates

| Situation | Action |
|---|---|
| No `state/discovery-state.json` in project root, or file exists with `engagement_type` unset | Ask "client" vs "own_product" first; do not proceed to any other question until answered. Then create/continue the file with `engagement_type` set and `coverage` initialized to all 20 categories `not_asked`. |
| `engagement_type: client`, file otherwise empty | Start with the `client` variant of category A's anchor question (see `assets/discovery-state.schema.json` and the coverage rule above). |
| `engagement_type: own_product`, file otherwise empty | Start with the `own_product` variant of category A's anchor question — frame `stakeholders` as the user roles in the founder's product, `processes` as the workflows the product supports, `business_rules` as the founder's stated assumptions/constraints. |
| File exists, `engagement_type` set | Load it, summarize current state (including how many `coverage` categories remain `not_asked`), continue from where it left off. |
| Hay categorías `required: true` en `not_asked` | La próxima pregunta es la ancla completa de la categoría obligatoria `not_asked` más temprana en orden A→T (variante según `engagement_type`). |
| Las 12 obligatorias están `touched`/`not_applicable`, pero quedan opcionales (`required: false`) en `not_asked` | La próxima pregunta es la pregunta corta de gating de la próxima opcional en orden K→T. |
| Se va a confirmar una regla nueva sobre un proceso que todavía no tiene entrada en `as_is_process` | Priorizar relevar el AS-IS de ese proceso antes de confirmar la regla — no aceptar la regla nueva sin el AS-IS relevado primero. |
| Las 20 categorías están `touched`/`not_applicable` (obligatorias con desarrollo completo, opcionales al menos con gating) | El discovery puede reportarse como completo; recién ahí se habilita continuar a `prd-agent`. |
| New statement, no conflict with confirmed rules, `client` mode | Append rule with next `RN-##` id, `stated_by` set to the speaking stakeholder, `status: confirmed`. |
| New statement is an unvalidated assumption about the user/market, `own_product` mode | Append rule with next `RN-##` id, `stated_by` set to the founder, `status: pending_clarification`, and add an `open_questions` entry asking for evidence. Do not confirm on the founder's word alone. |
| New statement conflicts with a confirmed rule from the **same** stakeholder | Set that rule's `status` to `pending_clarification`, add one entry to `open_questions` as `{id, question, item_ref}` (`item_ref` = the conflicting rule's id), do not confirm the new rule either. |
| New statement conflicts with a confirmed rule from a **different** stakeholder | Same handling (`pending_clarification` + `open_questions` entry), but the question must explicitly name both stakeholders and quote both statements — e.g. "El Vendedor pidió X; el Administrador ya había confirmado Y, que lo contradice. ¿Cuál aplica?" |

## Execution Steps

1. Load or initialize `state/discovery-state.json` (schema in `assets/discovery-state.schema.json`). If `engagement_type` is unset, ask for it before anything else and stop there for this turn; on a brand-new file, initialize `coverage` with all 20 categories `not_asked`.
2. Check `coverage`: if any `required: true` category is `not_asked`, the next question is that category's full anchor question (correct `engagement_type` variant). Else if any `required: false` category is `not_asked`, the next question is that category's short gating question. Only once every category is `touched`/`not_applicable` does step 2 defer to free-form follow-up within already-opened topics.
3. Extract stakeholders/processes/candidate rules/AS-IS steps/data points/integrations/security items/reports/notifications from the latest statement (the last five per the H/K/L/P/Q Hard Rule above), and identify which stakeholder is making it (or, in `own_product`, that it's the founder).
4. If the statement describes a new business rule about how a process *should* work, and `as_is_process` has no entry for that process yet, do not confirm the rule this turn — ask for the AS-IS first (Hard Rule above), then return to the rule once relevado.
5. Compare candidate rules and the statement against every `confirmed` rule for direct or implicit conflicts, regardless of which stakeholder stated the existing rule.
6. In `own_product` mode, additionally check whether the statement is an unvalidated assumption about the user/market rather than a directly observed fact; if so, challenge it per the Hard Rule above instead of confirming it.
7. Update the relevant `coverage` entry (`touched` with data captured, or `not_applicable` with `note`) for whatever category this turn's question belonged to.
8. Apply the matching Decision Gate row; update the state object in memory.
9. Write the full state back to `state/discovery-state.json`.
10. Report: what changed, any contradiction or unvalidated assumption found plus its clarifying question, how many `coverage` categories remain `not_asked` (obligatorias vs. opcionales), and the next single question to ask.

## Output Contract

Each turn ends with: the updated `state/discovery-state.json` on disk, a short summary of new/changed entries, the `coverage` status (X/12 obligatorias, Y/8 opcionales resueltas), any contradiction or challenged assumption with its clarifying question, and exactly one next question. The discovery is only reported as "completo" per the Decision Gates row above — never before. On request, output the full state file as the handoff artifact for the next pipeline stage (PRD), which reads `engagement_type` from here rather than asking again.

## References

- `../../../ingenieria_requerimientos_agentica.md` — overall multi-agent pipeline this stage feeds into; `engagement_type` modes and the own_product devil's-advocate risk in section 2; the `client`/`own_product` anchor-question reframing table.
- `../../../Manual-de-Analisis-de-Requerimientos.md`, sección 9 — the 20-category (A-T) question bank this skill's `coverage` checklist is built on. This skill never duplicates the questions; it only tracks which category was touched and references the manual for what to actually ask.
- `../../../prototype/discovery_agent.py` — standalone script validating the same contradiction-detection logic via the Claude API.
- `assets/discovery-state.schema.json` — state file shape (`schema_version: "1.3"` — adds `data_points`/`integrations`/`security_items`/`reports`/`notifications`, the first-class arrays backing categories H/K/L/P/Q so `prd-agent` can reference them 1:1 instead of by judgment).
