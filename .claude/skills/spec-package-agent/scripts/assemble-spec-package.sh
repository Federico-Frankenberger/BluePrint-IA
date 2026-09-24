#!/usr/bin/env bash
# Deterministic Spec Package assembler for the Ingeniería de Requerimientos Agentica pipeline.
# Read-only against every *-state.json / prd.md / propuesta.md / diagrams/*.mmd source.
# Writes only under spec-package/ (idempotent: wipes and rebuilds its own output tree).
# No jq/Python/Node dependency -- pure bash + GNU awk/sed, matching orchestrator-agent's precedent.
set -uo pipefail

ROOT="${1:-$(pwd)}"
OUT="$ROOT/spec-package"
DELIM=$'\x1e'

SUMMARY=()

# ============================================================
# Gate: Definition of Ready -- bloqueo duro, no advertencia.
# No se arma el paquete si el gate no pasa; se relaya su salida
# y se corta antes de tocar el directorio de salida.
# ============================================================
DOR_SCRIPT="$ROOT/.claude/skills/definition-of-ready-agent/scripts/check-definition-of-ready.sh"
if [ ! -f "$DOR_SCRIPT" ]; then
  echo "Spec Package NO ensamblado -- no se encontro el script de Definition of Ready ($DOR_SCRIPT)."
  echo "Sin ese chequeo no se puede verificar que el paquete este listo -- por diseno, esto tambien bloquea (fail closed, nunca fail open)."
  exit 1
fi
DOR_OUTPUT=$(bash "$DOR_SCRIPT" "$ROOT" 2>&1) || DOR_EXIT=$?
DOR_EXIT=${DOR_EXIT:-0}
if [ "$DOR_EXIT" -ne 0 ]; then
  if printf '%s\n' "$DOR_OUTPUT" | grep -q "^VEREDICTO: LEGACY$"; then
    echo "Spec Package NO ensamblado -- la corrida esta marcada LEGACY (congelada; exenta de completarse retroactivamente, no exenta del gate)."
  else
    echo "Spec Package NO ensamblado -- Definition of Ready no paso."
  fi
  echo ""
  echo "$DOR_OUTPUT"
  echo ""
  echo "Resolver lo de arriba y volver a correr /spec-package-agent."
  exit 1
fi
DOR_STATUS="passed"

rm -rf "$OUT"
mkdir -p "$OUT/product" "$OUT/requirements" "$OUT/user-stories" "$OUT/models" "$OUT/acceptance" "$OUT/estimation" "$OUT/proposal"

# --- extract raw top-level object blobs from a named JSON array (stdin).
#     Char-level scan (not a per-line regex-existence check): correctly
#     handles an opener and its objects sharing one physical line (e.g. a
#     one-line array with several objects), an array that opens and closes
#     on the very same line (e.g. "blocked": []), and ordinary
#     pretty-printed multi-line arrays alike. A naive "does this line
#     contain { or ]" check only fires once per line and never looks past
#     the position where it matched the arrays opener, so "blocked": []
#     on one line left the parser "inside" blocked and it silently
#     swallowed objects from the NEXT array instead. ---
extract_objects_stream() {
  local arr="$1"
  awk -v arr="$arr" -v RSEP="$DELIM" '
    BEGIN { in_arr=0; arrdepth=0; objdepth=0; buf="" }
    {
      line=$0
      n=length(line)
      i=1
      while (i <= n) {
        if (!in_arr) {
          rest = substr(line, i)
          if (match(rest, "\"" arr "\"[ \t]*:[ \t]*\\[")) {
            i = i + RSTART + RLENGTH - 1
            in_arr = 1
            arrdepth = 1
          } else {
            i = n + 1
          }
          continue
        }
        c = substr(line, i, 1)
        if (objdepth == 0) {
          if (c == "[") { arrdepth++ }
          else if (c == "]") {
            arrdepth--
            if (arrdepth == 0) { in_arr = 0; buf="" }
          }
          else if (c == "{") { objdepth++; buf = buf c }
        } else {
          buf = buf c
          if (c == "{") { objdepth++ }
          else if (c == "}") {
            objdepth--
            if (objdepth == 0) { printf "%s%s", buf, RSEP; buf="" }
          }
        }
        i++
      }
      # Preserve one physical-line-per-field granularity inside a still-open
      # object, same as the original line-buffered version, so downstream
      # sed field() extraction (which matches per line, first match wins)
      # keeps picking a records own top-level field over a same-named field
      # nested deeper inside it (e.g. a storys own "id" vs a nested
      # open_questions "id").
      if (in_arr==1 && objdepth>0) { buf = buf "\n" }
    }
  '
}

# --- extract a flat array of plain strings (stdin). Same char-level scan
#     as extract_objects_stream, for the same reason (a one-line or
#     opens-and-closes-on-one-line string array must not be misread). ---
extract_string_array_stream() {
  local arr="$1"
  awk -v arr="$arr" '
    BEGIN { in_arr=0; depth=0 }
    {
      line=$0
      n=length(line)
      i=1
      while (i <= n) {
        if (!in_arr) {
          rest = substr(line, i)
          if (match(rest, "\"" arr "\"[ \t]*:[ \t]*\\[")) {
            i = i + RSTART + RLENGTH - 1
            in_arr = 1
            depth = 1
          } else {
            i = n + 1
          }
          continue
        }
        c = substr(line, i, 1)
        if (c == "[") { depth++; i++ }
        else if (c == "]") {
          depth--
          i++
          if (depth == 0) { in_arr = 0 }
        }
        else if (c == "\"") {
          rest = substr(line, i)
          if (match(rest, /^"([^"]*)"/)) {
            if (depth == 1) { print substr(rest, 2, RLENGTH - 2) }
            i = i + RLENGTH
          } else { i++ }
        }
        else { i++ }
      }
    }
  '
}

# --- extract a single top-level JSON object by key from a text BLOB (not a
#     file) -- same char-depth scan used elsewhere in this script, but reads
#     a string already in hand (one story's own blob) instead of a file.
#     Used to surface a story's own "no_exception_reason" waiver, scoped to
#     that story only (same isolation discipline as check-definition-of-ready.sh). ---
extract_top_level_object_from_blob() {
  local blob="$1" key="$2"
  printf '%s' "$blob" | awk -v key="$key" '
    BEGIN { in_obj=0; depth=0 }
    {
      line=$0
      if (!in_obj) {
        pat = "\"" key "\""
        p = index(line, pat)
        if (p == 0) next
        rest = substr(line, p)
        b = index(rest, "{")
        if (b == 0) next
        in_obj = 1
        line = substr(rest, b)
      }
      n = length(line)
      for (i=1; i<=n; i++) {
        c = substr(line, i, 1)
        printf "%s", c
        if (c == "{") depth++
        else if (c == "}") {
          depth--
          if (depth == 0) { in_obj = 0; exit }
        }
      }
      printf "\n"
    }
  '
}

# --- pull "key": "value" from a text blob (first matching line) ---
field() {
  local blob="$1" key="$2"
  printf '%s' "$blob" | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -1
}

field_file() {
  local file="$1" key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -1
}

num_field_file() {
  local file="$1" key="$2"
  sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$file" | head -1
}

count_stream() {
  local n=0
  while IFS= read -r -d "$DELIM" b; do [ -n "$b" ] && n=$((n+1)); done
  echo "$n"
}

# --- normalize the "coverage" object into one physical line per category,
#     regardless of the source file's original line breaks/indentation
#     (same fix applied to definition-of-ready-agent's script). ---
normalize_coverage() {
  local file="$1"
  awk '
    BEGIN { in_cov=0; depth=0 }
    {
      line=$0
      if (!in_cov) {
        p = index(line, "\"coverage\"")
        if (p == 0) next
        rest = substr(line, p)
        b = index(rest, "{")
        if (b == 0) next
        in_cov = 1
        line = substr(rest, b)
      }
      n = length(line)
      for (i=1; i<=n; i++) {
        c = substr(line, i, 1)
        printf "%s", c
        if (c == "{") depth++
        else if (c == "}") {
          depth--
          if (depth == 0) { in_cov = 0; exit }
        }
      }
      printf " "
    }
  ' "$file" | sed -E 's/"([A-Z]_[a-z_]+)"[ \t]*:/\n"\1":/g'
}

# ============================================================
# product/prd.md + product/personas.md  (source: prd-state.json, prd.md)
# ============================================================
if [ -f "$ROOT/source/prd.md" ]; then
  cp "$ROOT/source/prd.md" "$OUT/product/prd.md"
else
  echo "_prd.md no existe todavía -- correr /prd-agent._" > "$OUT/product/prd.md"
fi

if [ -f "$ROOT/state/prd-state.json" ]; then
  {
    echo "# Personas"
    echo
    echo "| ID | Nombre | Nivel técnico | Necesidades | Fuente |"
    echo "|---|---|---|---|---|"
  } > "$OUT/product/personas.md"
  p_count=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    p_count=$((p_count+1))
    id=$(field "$blob" id); name=$(field "$blob" name); src=$(field "$blob" source)
    tech=$(field "$blob" technical_level); needs=$(field "$blob" needs)
    echo "| $id | $name | ${tech:-—} | ${needs:-—} | $src |" >> "$OUT/product/personas.md"
  done < <(extract_objects_stream personas < "$ROOT/state/prd-state.json")
  SUMMARY+=("product/personas.md: $p_count personas")
else
  echo "_prd-state.json no existe todavía._" > "$OUT/product/personas.md"
fi

# ============================================================
# requirements/functional.md + non-functional.md  (source: requirements-state.json)
# ============================================================
gen_requirements() {
  local type="$1" outfile="$2" label="$3"
  local total=0 confirmed=0
  {
    echo "# Requerimientos $label"
    echo
  } > "$outfile"
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    t=$(field "$blob" type)
    [ "$t" != "$type" ] && continue
    total=$((total+1))
    st=$(field "$blob" status)
    if [ "$st" = "confirmed" ]; then
      confirmed=$((confirmed+1))
      id=$(field "$blob" id); text=$(field "$blob" text); src=$(field "$blob" source); prio=$(field "$blob" priority)
      printf -- "- **%s** _[%s]_: %s _(fuente: %s)_\n" "$id" "${prio:-sin prioridad}" "$text" "$src" >> "$outfile"
    fi
  done < <(extract_objects_stream requirements < "$ROOT/state/requirements-state.json")
  if [ "$confirmed" -eq 0 ]; then
    echo "_Ninguno confirmado todavía._" >> "$outfile"
  fi
  SUMMARY+=("$(basename "$outfile"): $confirmed confirmados de $total candidatos $type")
}

if [ -f "$ROOT/state/requirements-state.json" ]; then
  gen_requirements "RF" "$OUT/requirements/functional.md" "funcionales"
  gen_requirements "RNF" "$OUT/requirements/non-functional.md" "no funcionales"

  rej_count=$(extract_objects_stream rejected < "$ROOT/state/requirements-state.json" | count_stream)
  blk_count=$(extract_objects_stream blocked < "$ROOT/state/requirements-state.json" | count_stream)
  SUMMARY+=("requirements-state.json: $rej_count rejected (prd_out_of_scope u otro), $blk_count blocked -- no incluidos en functional/non-functional.md")
else
  echo "_requirements-state.json no existe todavía._" > "$OUT/requirements/functional.md"
  echo "_requirements-state.json no existe todavía._" > "$OUT/requirements/non-functional.md"
fi

# ============================================================
# requirements/business-rules.md  (source: discovery-state.json)
# ============================================================
if [ -f "$ROOT/state/discovery-state.json" ]; then
  {
    echo "# Reglas de negocio"
    echo
  } > "$OUT/requirements/business-rules.md"
  br_total=0; br_confirmed=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    br_total=$((br_total+1))
    st=$(field "$blob" status)
    [ "$st" != "confirmed" ] && continue
    br_confirmed=$((br_confirmed+1))
    id=$(field "$blob" id); text=$(field "$blob" text); by=$(field "$blob" stated_by)
    echo "- **$id:** $text _(dicho por: ${by:-no registrado})_" >> "$OUT/requirements/business-rules.md"
  done < <(extract_objects_stream business_rules < "$ROOT/state/discovery-state.json")
  SUMMARY+=("business-rules.md: $br_confirmed confirmadas de $br_total relevadas (RN-03/RN-04 confirmadas aquí -- fueron excluidas río abajo en requirements, no en discovery)")
else
  echo "_discovery-state.json no existe todavía._" > "$OUT/requirements/business-rules.md"
fi

# ============================================================
# user-stories/US-XXX.md + acceptance/acceptance-criteria.md  (source: user-stories-state.json)
# ============================================================
render_gherkin_block() {
  local blob="$1"
  echo '```gherkin'
  while IFS= read -r -d "$DELIM" ac; do
    [ -z "$ac" ] && continue
    g=$(field "$ac" given); w=$(field "$ac" when); t=$(field "$ac" then)
    echo "Given $g"
    echo "When $w"
    echo "Then $t"
  done < <(printf '%s' "$blob" | extract_objects_stream acceptance_criteria)
  echo '```'
}

if [ -f "$ROOT/state/user-stories-state.json" ]; then
  {
    echo "# Criterios de aceptación consolidados"
    echo
  } > "$OUT/acceptance/acceptance-criteria.md"

  us_count=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    us_count=$((us_count+1))
    id=$(field "$blob" id); actor=$(field "$blob" actor)
    action=$(field "$blob" action); benefit=$(field "$blob" benefit)
    src=$(field "$blob" source); prio=$(field "$blob" priority)

    {
      echo "# $id"
      echo
      echo "**Como** $actor"
      echo "**quiero** $action"
      echo "**para** $benefit"
      echo
      echo "_Fuente: ${src}_ · _Prioridad: ${prio:-sin asignar}_"
      echo
      echo "## Criterios de aceptación"
      echo
      render_gherkin_block "$blob"

      oq_count=0
      oq_block=""
      while IFS= read -r -d "$DELIM" oq; do
        [ -z "$oq" ] && continue
        oq_count=$((oq_count+1))
        q=$(field "$oq" question)
        oq_block="${oq_block}- ${q}"$'\n'
      done < <(printf '%s' "$blob" | extract_objects_stream open_questions)
      if [ "$oq_count" -gt 0 ]; then
        echo
        echo "## Open questions"
        echo
        printf '%s' "$oq_block"
      fi

      waiver_blob=$(extract_top_level_object_from_blob "$blob" no_exception_reason)
      waiver_reason=$(field "$waiver_blob" reason)
      waiver_by=$(field "$waiver_blob" stated_by)
      if [ -n "$waiver_reason" ]; then
        echo
        echo "## Waiver de excepción"
        echo
        echo "Sin AC de tipo \`exception\` -- $waiver_reason _(stated_by: ${waiver_by:-sin registrar})_"
      fi
    } > "$OUT/user-stories/${id}.md"

    {
      echo "## $id"
      echo
      render_gherkin_block "$blob"
      echo
    } >> "$OUT/acceptance/acceptance-criteria.md"
  done < <(extract_objects_stream stories < "$ROOT/state/user-stories-state.json")

  skipped_count=$(extract_objects_stream skipped < "$ROOT/state/user-stories-state.json" | count_stream)
  SUMMARY+=("user-stories/: $us_count historias generadas, $skipped_count RNF skipped (no aplica -- no es un estado 'sin resolver')")
else
  echo "_user-stories-state.json no existe todavía._" > "$OUT/acceptance/acceptance-criteria.md"
fi

# ============================================================
# models/*.mmd  (source: diagrams/*.mmd -- copied verbatim)
# ============================================================
if compgen -G "$ROOT/diagrams/*.mmd" > /dev/null 2>&1; then
  cp "$ROOT"/diagrams/*.mmd "$OUT/models/"
  mmd_count=$(ls "$ROOT"/diagrams/*.mmd 2>/dev/null | wc -l | tr -d ' ')
else
  mmd_count=0
fi
if [ -f "$ROOT/state/uml-state.json" ]; then
  uml_blocked=$(extract_objects_stream blocked < "$ROOT/state/uml-state.json" | count_stream)
else
  uml_blocked=0
fi
SUMMARY+=("models/: $mmd_count diagramas copiados, $uml_blocked bloqueados en UML (class/erd) -- no generados, no incluidos")

# ============================================================
# estimation/estimate.md  (source: estimation-state.json)
# ============================================================
if [ -f "$ROOT/state/estimation-state.json" ]; then
  min=$(num_field_file "$ROOT/state/estimation-state.json" min)
  max=$(num_field_file "$ROOT/state/estimation-state.json" max)
  team=$(field_file "$ROOT/state/estimation-state.json" team)
  unc=$(field_file "$ROOT/state/estimation-state.json" uncertainty)
  {
    echo "# Estimación preliminar"
    echo
    echo "- Duración estimada: ${min}–${max} semanas"
    echo "- Equipo: $team"
    echo "- Nivel de incertidumbre: $unc"
    echo
    echo "## Riesgos"
    echo
    r_lines=$(extract_string_array_stream global_risks < "$ROOT/state/estimation-state.json")
    if [ -n "$r_lines" ]; then printf '%s\n' "$r_lines" | while IFS= read -r a; do [ -n "$a" ] && echo "- $a"; done; else echo "_Ninguno registrado._"; fi
    echo
    echo "## Supuestos"
    echo
    a_lines=$(extract_string_array_stream global_assumptions < "$ROOT/state/estimation-state.json")
    if [ -n "$a_lines" ]; then printf '%s\n' "$a_lines" | while IFS= read -r a; do [ -n "$a" ] && echo "- $a"; done; else echo "_Ninguno registrado._"; fi
    echo
    echo "## Dependencias"
    echo
    d_lines=$(extract_string_array_stream global_dependencies < "$ROOT/state/estimation-state.json")
    if [ -n "$d_lines" ]; then printf '%s\n' "$d_lines" | while IFS= read -r a; do [ -n "$a" ] && echo "- $a"; done; else echo "_Ninguna registrada._"; fi
  } > "$OUT/estimation/estimate.md"
  SUMMARY+=("estimation/estimate.md: rango ${min}-${max} semanas, incertidumbre $unc")
else
  echo "_estimation-state.json no existe todavía._" > "$OUT/estimation/estimate.md"
fi

# ============================================================
# proposal/commercial-proposal.md  (source: propuesta.md)
# ============================================================
if [ -f "$ROOT/source/propuesta.md" ]; then
  cp "$ROOT/source/propuesta.md" "$OUT/proposal/commercial-proposal.md"
  SUMMARY+=("proposal/commercial-proposal.md: copiado desde propuesta.md")
else
  echo "_propuesta.md no existe todavía -- correr /proposal-agent._" > "$OUT/proposal/commercial-proposal.md"
fi

# ============================================================
# product/as-is-to-be.md  (source: discovery-state.json.as_is_process / to_be_process)
# ============================================================
if [ -f "$ROOT/state/discovery-state.json" ]; then
  {
    echo "# AS-IS / TO-BE"
    echo
    echo "## Proceso actual (AS-IS)"
    echo
  } > "$OUT/product/as-is-to-be.md"
  as_is_count=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    as_is_count=$((as_is_count+1))
    step=$(field "$blob" step); actor=$(field "$blob" actor)
    herr=$(field "$blob" herramienta_actual); prob=$(field "$blob" problema_detectado)
    {
      echo "$as_is_count. **$step** ($actor) — herramienta actual: $herr"
      if [ -n "$prob" ] && [ "$prob" != "null" ]; then echo "   - Problema detectado: $prob"; fi
    } >> "$OUT/product/as-is-to-be.md"
  done < <(extract_objects_stream as_is_process < "$ROOT/state/discovery-state.json")
  [ "$as_is_count" -eq 0 ] && echo "_Ninguno relevado todavía._" >> "$OUT/product/as-is-to-be.md"

  { echo; echo "## Proceso futuro (TO-BE)"; echo; } >> "$OUT/product/as-is-to-be.md"
  to_be_count=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    to_be_count=$((to_be_count+1))
    step=$(field "$blob" step); actor=$(field "$blob" actor); cambio=$(field "$blob" cambio_respecto_as_is)
    echo "$to_be_count. **$step** ($actor) — $cambio" >> "$OUT/product/as-is-to-be.md"
  done < <(extract_objects_stream to_be_process < "$ROOT/state/discovery-state.json")
  [ "$to_be_count" -eq 0 ] && echo "_Ninguno derivado todavía._" >> "$OUT/product/as-is-to-be.md"
  SUMMARY+=("product/as-is-to-be.md: $as_is_count pasos AS-IS, $to_be_count pasos TO-BE")
else
  echo "_discovery-state.json no existe todavía._" > "$OUT/product/as-is-to-be.md"
fi

# ============================================================
# product/coverage-report.md  (source: discovery-state.json.coverage)
# Asume una entrada de coverage por linea fisica (convencion schema v1.2).
# ============================================================
if [ -f "$ROOT/state/discovery-state.json" ]; then
  {
    echo "# Cobertura del Discovery"
    echo
    echo "Las 20 categorías del banco de preguntas (Manual-de-Analisis-de-Requerimientos.md, sección 9). Obligatorias: A-J, R, S -- bloquean el cierre. Opcionales (con gating): K-Q, T."
    echo
    echo "| Categoría | Obligatoria | Estado | Nota |"
    echo "|---|---|---|---|"
  } > "$OUT/product/coverage-report.md"
  COV_NORMALIZED=$(normalize_coverage "$ROOT/state/discovery-state.json")
  CATS="A_contexto_general B_problema_actual C_objetivos_negocio D_stakeholders E_usuarios F_procesos_negocio G_funcionalidades H_datos I_reglas_negocio J_casos_excepcionales K_integraciones L_seguridad M_requisitos_no_funcionales N_infraestructura O_regulaciones P_reportes Q_notificaciones R_alcance S_prioridades T_futuro"
  cov_resolved=0; cov_total=0
  for cat in $CATS; do
    cov_total=$((cov_total+1))
    line=$(printf '%s\n' "$COV_NORMALIZED" | grep "\"$cat\"" | head -1)
    status=$(printf '%s' "$line" | sed -nE 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
    if printf '%s' "$line" | grep -q '"required": *true'; then required="sí"; else required="no"; fi
    note=$(printf '%s' "$line" | sed -nE 's/.*"note"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
    if [ "$status" = "touched" ] || [ "$status" = "not_applicable" ]; then cov_resolved=$((cov_resolved+1)); fi
    echo "| $cat | $required | ${status:-not_asked} | ${note:--} |" >> "$OUT/product/coverage-report.md"
  done
  SUMMARY+=("product/coverage-report.md: $cov_resolved de $cov_total categorías resueltas")
else
  echo "_discovery-state.json no existe todavía._" > "$OUT/product/coverage-report.md"
fi

# ============================================================
# product/glossary.md  (source: ninguno todavía)
# Ninguna skill del pipeline captura terminos de glosario hoy --
# nunca se fabrica contenido para un archivo que nada respalda
# (mismo principio que architecture/, ver manifest.not_backed).
# ============================================================
{
  echo "# Glosario de términos del dominio"
  echo
  echo "_Ninguna skill del pipeline captura términos de glosario todavía -- este archivo existe como destino reservado, no se fabrica contenido para él (mismo principio que \`architecture/\`: ver \`not_backed\` en manifest.json)._"
} > "$OUT/product/glossary.md"

# ============================================================
# acceptance/definition-of-ready.md  (source: la corrida de DoR de mas arriba)
# ============================================================
{
  echo "# Definition of Ready"
  echo
  echo '```'
  echo "$DOR_OUTPUT"
  echo '```'
} > "$OUT/acceptance/definition-of-ready.md"

# ============================================================
# acceptance/open-questions.md  (source: discovery-state.json + cada historia)
# Por construccion, si llegamos hasta aca el gate de DoR ya paso,
# asi que esto deberia listar cero preguntas sin resolver -- es una
# confirmacion positiva, no solo un archivo de agregacion.
# ============================================================
{
  echo "# Preguntas abiertas"
  echo
} > "$OUT/acceptance/open-questions.md"
oq_total=0
if [ -f "$ROOT/state/discovery-state.json" ]; then
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    oq_total=$((oq_total+1))
    q=$(field "$blob" question)
    echo "- _(discovery)_ $q" >> "$OUT/acceptance/open-questions.md"
  done < <(extract_objects_stream open_questions < "$ROOT/state/discovery-state.json")
fi
if [ -f "$ROOT/state/user-stories-state.json" ]; then
  while IFS= read -r -d "$DELIM" sblob; do
    [ -z "$sblob" ] && continue
    sid=$(field "$sblob" id)
    while IFS= read -r -d "$DELIM" oqblob; do
      [ -z "$oqblob" ] && continue
      oq_total=$((oq_total+1))
      q=$(field "$oqblob" question)
      echo "- _($sid)_ $q" >> "$OUT/acceptance/open-questions.md"
    done < <(printf '%s' "$sblob" | extract_objects_stream open_questions)
  done < <(extract_objects_stream stories < "$ROOT/state/user-stories-state.json")
fi
if [ "$oq_total" -eq 0 ]; then
  echo "_Ninguna pregunta abierta pendiente -- consistente con que Definition of Ready haya pasado._" >> "$OUT/acceptance/open-questions.md"
fi
SUMMARY+=("acceptance/open-questions.md: $oq_total preguntas listadas")

# ============================================================
# manifest.json -- index of skill schemas -> spec-package files they back
#
# contract_version: bump whenever the shape of this file changes (a new
# top-level key, a changed folder layout) so an external consumer (any SDD
# reading this cold) can detect drift instead of silently mis-parsing it.
#
# exclusion_summary: the same per-file counts this script prints to stdout
# (SUMMARY array), persisted here too. Printing them to chat only means an
# external SDD reading manifest.json outside this session never sees them --
# it would have to re-open every *-state.json and recount. See document
# section 14 (Manual Técnico): the boundary principle requires this pipeline
# to be honest about what's open, not just what's confirmed.
# ============================================================
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

{
  cat <<EOF
{
  "contract_version": "1.1",
  "generated_by": "spec-package-agent/scripts/assemble-spec-package.sh",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dor_status": "$DOR_STATUS",
  "sources": [
    { "skill": "discovery-agent", "schema": "../.claude/skills/discovery-agent/assets/discovery-state.schema.json", "produces": ["requirements/business-rules.md", "product/as-is-to-be.md", "product/coverage-report.md"] },
    { "skill": "prd-agent", "schema": "../.claude/skills/prd-agent/assets/prd-state.schema.json", "produces": ["product/prd.md", "product/personas.md"] },
    { "skill": "requirements-agent", "schema": "../.claude/skills/requirements-agent/assets/requirements-state.schema.json", "produces": ["requirements/functional.md", "requirements/non-functional.md"] },
    { "skill": "user-stories-agent", "schema": "../.claude/skills/user-stories-agent/assets/user-stories-state.schema.json", "produces": ["user-stories/*.md", "acceptance/acceptance-criteria.md"] },
    { "skill": "uml-agent", "schema": "../.claude/skills/uml-agent/assets/uml-state.schema.json", "produces": ["models/*.mmd"] },
    { "skill": "estimation-agent", "schema": "../.claude/skills/estimation-agent/assets/estimation-state.schema.json", "produces": ["estimation/estimate.md"] },
    { "skill": "proposal-agent", "schema": "../.claude/skills/proposal-agent/assets/proposal-state.schema.json", "produces": ["proposal/commercial-proposal.md"] },
    { "skill": "definition-of-ready-agent", "schema": null, "produces": ["acceptance/definition-of-ready.md"] },
    { "skill": "spec-package-agent", "schema": null, "produces": ["acceptance/open-questions.md"], "note": "agregación propia sobre discovery-state.json y user-stories-state.json, no un schema nuevo" }
  ],
  "not_backed": [
    "architecture/ -- fuera de alcance por diseño: arquitectura y modelo de datos son responsabilidad del SDD consumidor que reciba este spec package, nunca de este pipeline",
    "product/glossary.md -- ninguna skill del pipeline captura términos de glosario todavía; archivo reservado, nunca se fabrica contenido para él"
  ],
  "exclusion_summary": [
EOF
  n=${#SUMMARY[@]}
  for i in "${!SUMMARY[@]}"; do
    line=$(json_escape "${SUMMARY[$i]}")
    if [ "$i" -lt $((n-1)) ]; then
      printf '    "%s",\n' "$line"
    else
      printf '    "%s"\n' "$line"
    fi
  done
  cat <<EOF
  ]
}
EOF
} > "$OUT/manifest.json"

# ============================================================
# Final report
# ============================================================
echo "Spec Package ensamblado en: $OUT"
echo ""
echo "Resumen de exclusiones (nada desaparece en silencio):"
for line in "${SUMMARY[@]}"; do
  echo "  - $line"
done
