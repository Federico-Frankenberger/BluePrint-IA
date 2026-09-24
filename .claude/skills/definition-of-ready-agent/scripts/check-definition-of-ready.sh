#!/usr/bin/env bash
# Deterministic Definition of Ready gate for the Ingeniería de Requerimientos Agentica pipeline.
# Read-only against state/*.json -- writes nothing, matching orchestrator-agent's precedent
# (no LLM reasoning: this is rules over fields, not judgment).
# No jq/Python/Node dependency -- pure bash + GNU awk/sed, same pattern as spec-package-agent.
set -uo pipefail

ROOT="${1:-$(pwd)}"
DELIM=$'\x1e'

PASS=()
FAIL=()
WAIVED=()

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

# --- pull "key": "value" from a text blob (first matching line) ---
field() {
  local blob="$1" key="$2"
  printf '%s' "$blob" | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" | head -1
}

# --- pull "key": true|false (unquoted literal) from a text blob ---
bool_field() {
  local blob="$1" key="$2"
  printf '%s' "$blob" | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" | head -1
}

# --- extract a single top-level JSON object by key (not an array element --
#     e.g. "legacy": {...}). Same brace-depth scan as normalize_coverage,
#     but keeps physical-line granularity so field()/bool_field() (which
#     match one key per line) still work whether the source is pretty-printed
#     or one-line JSON. ---
extract_top_level_object() {
  local file="$1" key="$2"
  awk -v key="$key" '
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
  ' "$file"
}

count_stream() {
  local n=0
  while IFS= read -r -d "$DELIM" b; do [ -n "$b" ] && n=$((n+1)); done
  echo "$n"
}

# --- extract a single top-level JSON object by key from a text BLOB (not a
#     file) -- same char-depth scan as extract_top_level_object below, but
#     reads from a string already in hand (e.g. one story's own blob from
#     extract_objects_stream) instead of a file. Used to pull a story's own
#     "no_exception_reason" object without ever reading past that story's
#     own closing brace -- so a waiver on one HU can never "leak" and
#     satisfy a different HU (same isolation discipline as ac_exception_count
#     below, which is computed on this same per-story blob). ---
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

# --- normalize the "coverage" object into one physical line per category,
#     regardless of the source file's original line breaks/indentation.
#     A pure grep-per-original-line approach silently reports everything as
#     OK when the file is pretty-printed (one field per line) instead of one
#     category per line -- this fixes that false-pass. ---
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

if [ ! -f "$ROOT/state/user-stories-state.json" ]; then
  echo "Definition of Ready: no se puede evaluar -- state/user-stories-state.json no existe todavia."
  echo "Siguiente paso: correr discovery-agent -> prd-agent -> requirements-agent -> user-stories-agent primero."
  exit 1
fi

# ============================================================
# 0. Legacy: una corrida puede estar marcada como congelada
#    (discovery-state.json.legacy, ver Plan-de-Mejora-Pipeline.md
#    punto 11). Legacy NUNCA hace pasar el gate -- solo cambia el
#    reporte a un estado distinto, sigue bloqueando spec-package-agent.
#    Fail closed: un marcador ausente, parcial o mal formado (is_legacy
#    no es literalmente `true`, o falta reason/marked_at) se trata como
#    NO legacy y cae al flujo normal de FAILED/PASSED.
# ============================================================
IS_LEGACY=0
LEGACY_REASON=""
LEGACY_MARKED_AT=""
LEGACY_PREDATES=""
if [ -f "$ROOT/state/discovery-state.json" ]; then
  LEGACY_BLOB=$(extract_top_level_object "$ROOT/state/discovery-state.json" legacy)
  if [ -n "$LEGACY_BLOB" ]; then
    LEGACY_IS=$(bool_field "$LEGACY_BLOB" is_legacy)
    LEGACY_REASON=$(field "$LEGACY_BLOB" reason)
    LEGACY_MARKED_AT=$(field "$LEGACY_BLOB" marked_at)
    LEGACY_PREDATES=$(field "$LEGACY_BLOB" predates_schema_version)
    if [ "$LEGACY_IS" = "true" ] && [ -n "$LEGACY_REASON" ] && [ -n "$LEGACY_MARKED_AT" ]; then
      IS_LEGACY=1
    fi
  fi
fi

# ============================================================
# 1. Cobertura de discovery-agent: las 12 categorias obligatorias
#    deben estar touched|not_applicable. Asume una entrada de
#    coverage por linea fisica (convencion del schema v1.2).
# ============================================================
DISCOVERY_OK=1
DISCOVERY_DETAIL=""
DISCOVERY_OQ_COUNT=0

if [ -f "$ROOT/state/discovery-state.json" ]; then
  NOT_READY_REQUIRED=$(normalize_coverage "$ROOT/state/discovery-state.json" 2>/dev/null \
    | grep '"required": *true' \
    | grep -v '"status": *"touched"' \
    | grep -v '"status": *"not_applicable"' \
    | grep -oE '"[A-Z]_[a-z_]+"' | head -1 || true)
  if [ -n "$NOT_READY_REQUIRED" ]; then
    DISCOVERY_OK=0
    DISCOVERY_DETAIL="Categoria obligatoria $NOT_READY_REQUIRED sin cubrir en discovery-state.json -- correr discovery-agent de nuevo."
  fi
  DISCOVERY_OQ_COUNT=$(extract_objects_stream open_questions < "$ROOT/state/discovery-state.json" | count_stream)
  if [ "$DISCOVERY_OQ_COUNT" -gt 0 ]; then
    DISCOVERY_OK=0
    DISCOVERY_DETAIL="${DISCOVERY_DETAIL}${DISCOVERY_DETAIL:+ }discovery-state.json tiene $DISCOVERY_OQ_COUNT open_questions sin resolver -- correr discovery-agent de nuevo para cerrarlas."
  fi
else
  DISCOVERY_OK=0
  DISCOVERY_DETAIL="state/discovery-state.json no existe -- correr discovery-agent primero."
fi

# ============================================================
# 2. Por cada historia confirmada: priority, al menos un AC,
#    RF fuente confirmed, sin open_questions sin resolver.
# ============================================================
rf_status_of() {
  local rf_id="$1"
  [ -f "$ROOT/state/requirements-state.json" ] || { echo ""; return; }
  local found=""
  while IFS= read -r -d "$DELIM" rblob; do
    [ -z "$rblob" ] && continue
    local rid; rid=$(field "$rblob" id)
    if [ "$rid" = "$rf_id" ]; then found=$(field "$rblob" status); break; fi
  done < <(extract_objects_stream requirements < "$ROOT/state/requirements-state.json")
  echo "$found"
}

STORY_COUNT=0
while IFS= read -r -d "$DELIM" blob; do
  [ -z "$blob" ] && continue
  STORY_COUNT=$((STORY_COUNT+1))
  id=$(field "$blob" id)
  priority=$(field "$blob" priority)
  source=$(field "$blob" source)
  oq_count=$(printf '%s' "$blob" | extract_objects_stream open_questions | count_stream)
  ac_count=$(printf '%s' "$blob" | extract_objects_stream acceptance_criteria | count_stream)
  ac_exception_count=0
  while IFS= read -r -d "$DELIM" acblob; do
    [ -z "$acblob" ] && continue
    ac_type=$(field "$acblob" type)
    if [ "$ac_type" = "exception" ]; then
      ac_exception_count=$((ac_exception_count+1))
    fi
  done < <(printf '%s' "$blob" | extract_objects_stream acceptance_criteria)

  # --- explicit waiver: a story with no exception AC can still pass this
  #     check when a stakeholder explicitly confirmed no exception applies
  #     (user-stories-agent's own Hard Rule -- see SKILL.md -- never invents
  #     an exception AC to satisfy this gate). Fail closed on anything less
  #     than a well-formed waiver: `reason` and `stated_by` both non-empty.
  #     A present-but-malformed waiver (empty reason, missing/empty
  #     stated_by) gets its own distinct actionable message -- it must never
  #     silently fall back to being treated as "no waiver at all", because
  #     that would hide a broken waiver behind the generic missing-AC text. ---
  waiver_blob=$(extract_top_level_object_from_blob "$blob" no_exception_reason)
  waiver_reason=$(field "$waiver_blob" reason)
  waiver_stated_by=$(field "$waiver_blob" stated_by)
  waiver_present=0
  [ -n "$waiver_blob" ] && waiver_present=1
  waiver_ok=0
  if [ -n "$waiver_reason" ] && [ -n "$waiver_stated_by" ]; then
    waiver_ok=1
  fi

  rf_status=$(rf_status_of "$source")

  reasons=()
  if [ -z "$priority" ] || [ "$priority" = "null" ]; then
    reasons+=("sin priority asignada -- correr requirements-agent de nuevo, requisito $source")
  fi
  if [ "$ac_count" -eq 0 ]; then
    reasons+=("sin acceptance_criteria -- correr user-stories-agent de nuevo")
  elif [ "$ac_exception_count" -eq 0 ]; then
    if [ "$waiver_ok" -eq 1 ]; then
      WAIVED+=("$id: sin excepción — waiver: $waiver_reason (stated_by $waiver_stated_by)")
    elif [ "$waiver_present" -eq 1 ]; then
      reasons+=("no_exception_reason mal formado (falta reason y/o stated_by) -- correr user-stories-agent de nuevo, historia $id")
    else
      reasons+=("sin criterio de aceptación de excepción -- correr user-stories-agent de nuevo, historia $id")
    fi
  fi
  if [ "$oq_count" -gt 0 ]; then
    reasons+=("tiene $oq_count open_questions sin resolver -- correr discovery-agent o user-stories-agent de nuevo")
  fi
  if [ -n "$source" ] && [ "$rf_status" != "confirmed" ]; then
    reasons+=("su requisito fuente $source no esta confirmed (status: '${rf_status:-desconocido}') -- revisar requirements-agent")
  fi

  if [ ${#reasons[@]} -eq 0 ]; then
    PASS+=("$id")
  else
    joined=""
    for r in "${reasons[@]}"; do
      if [ -z "$joined" ]; then joined="$r"; else joined="$joined; $r"; fi
    done
    FAIL+=("$id: $joined")
  fi
done < <(extract_objects_stream stories < "$ROOT/state/user-stories-state.json")

# ============================================================
# Reporte final
# ============================================================
PASS_COUNT=${#PASS[@]}
FAIL_COUNT=${#FAIL[@]}

echo "Definition of Ready -- $STORY_COUNT historias evaluadas"
echo ""

if [ "$IS_LEGACY" -eq 1 ]; then
  echo "Estado: LEGACY -- corrida congelada. Exenta de completarse retroactivamente, NO exenta del gate (sigue bloqueando spec-package-agent)."
  echo "  Motivo: $LEGACY_REASON"
  echo "  Marcada el: $LEGACY_MARKED_AT"
  echo "  Predates schema_version: ${LEGACY_PREDATES:-desconocido (corrida anterior al propio campo schema_version)}"
  echo "  Accionable: para reabrirla, correr discovery-agent de nuevo y completar coverage/priority/acceptance_criteria faltantes; recien ahi se puede re-evaluar normalmente (retirando el marcador legacy)."
  echo ""
fi

if [ "$DISCOVERY_OK" -eq 1 ]; then
  echo "Cobertura de discovery: OK (12/12 obligatorias, 0 open_questions sin resolver)"
else
  echo "Cobertura de discovery: FALLA -- $DISCOVERY_DETAIL"
fi
echo ""

echo "Historias listas ($PASS_COUNT/$STORY_COUNT):"
for p in "${PASS[@]:-}"; do
  [ -n "$p" ] && echo "  - $p"
done
echo ""

WAIVED_COUNT=${#WAIVED[@]}
if [ "$WAIVED_COUNT" -gt 0 ]; then
  echo "Historias con waiver de excepción ($WAIVED_COUNT) -- pasan el gate sin AC de tipo exception, por confirmación explícita de un stakeholder:"
  for w in "${WAIVED[@]}"; do
    echo "  - $w"
  done
  echo ""
fi

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "Historias NO listas ($FAIL_COUNT/$STORY_COUNT):"
  for f in "${FAIL[@]}"; do
    echo "  - $f"
  done
fi

echo ""
if [ "$IS_LEGACY" -eq 1 ]; then
  echo "VEREDICTO: LEGACY"
  exit 3
elif [ "$DISCOVERY_OK" -eq 1 ] && [ "$FAIL_COUNT" -eq 0 ] && [ "$STORY_COUNT" -gt 0 ]; then
  echo "VEREDICTO: PASSED"
  exit 0
else
  echo "VEREDICTO: FAILED"
  exit 2
fi
