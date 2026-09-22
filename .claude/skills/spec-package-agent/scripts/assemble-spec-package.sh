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

rm -rf "$OUT"
mkdir -p "$OUT/product" "$OUT/requirements" "$OUT/user-stories" "$OUT/models" "$OUT/acceptance" "$OUT/estimation" "$OUT/proposal"

# --- extract raw top-level object blobs from a named JSON array (stdin), depth-tracked on { } ---
extract_objects_stream() {
  local arr="$1"
  awk -v arr="$arr" -v RSEP="$DELIM" '
    BEGIN { in_arr=0; depth=0; buf="" }
    {
      if (!in_arr) {
        if ($0 ~ "\"" arr "\"[ \t]*:[ \t]*\\[") { in_arr=1 }
        next
      }
      if (depth==0 && $0 ~ /\]/) { in_arr=0; next }
      if ($0 ~ /\{/) { depth++ }
      if (depth>0) { buf = buf $0 "\n" }
      if ($0 ~ /\}/) {
        depth--
        if (depth==0) { printf "%s%s", buf, RSEP; buf="" }
      }
    }
  '
}

# --- extract a flat array of plain strings (stdin) ---
extract_string_array_stream() {
  local arr="$1"
  awk -v arr="$arr" '
    BEGIN { in_arr=0 }
    {
      if (!in_arr) { if ($0 ~ "\"" arr "\"[ \t]*:[ \t]*\\[") { in_arr=1 }; next }
      if ($0 ~ /\]/) { in_arr=0; next }
      if (match($0, /"([^"]*)"/, m)) { print m[1] }
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
    echo "| ID | Nombre | Fuente |"
    echo "|---|---|---|"
  } > "$OUT/product/personas.md"
  p_count=0
  while IFS= read -r -d "$DELIM" blob; do
    [ -z "$blob" ] && continue
    p_count=$((p_count+1))
    id=$(field "$blob" id); name=$(field "$blob" name); src=$(field "$blob" source)
    echo "| $id | $name | $src |" >> "$OUT/product/personas.md"
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
      id=$(field "$blob" id); text=$(field "$blob" text); src=$(field "$blob" source)
      printf -- "- **%s:** %s _(fuente: %s)_\n" "$id" "$text" "$src" >> "$outfile"
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
    id=$(field "$blob" id); text=$(field "$blob" text)
    echo "- **$id:** $text" >> "$OUT/requirements/business-rules.md"
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
    src=$(field "$blob" source)

    {
      echo "# $id"
      echo
      echo "**Como** $actor"
      echo "**quiero** $action"
      echo "**para** $benefit"
      echo
      echo "_Fuente: ${src}_"
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
    } > "$OUT/user-stories/${id}.md"

    {
      echo "## $id"
      echo
      render_gherkin_block "$blob"
      echo
    } >> "$OUT/acceptance/acceptance-criteria.md"
  done < <(extract_objects_stream stories < "$ROOT/state/user-stories-state.json")

  skipped_count=$(extract_string_array_stream skipped < "$ROOT/state/user-stories-state.json" | wc -l | tr -d ' ')
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
    echo "## Supuestos"
    echo
    extract_string_array_stream global_assumptions < "$ROOT/state/estimation-state.json" | while IFS= read -r a; do
      echo "- $a"
    done
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
  "contract_version": "1.0",
  "generated_by": "spec-package-agent/scripts/assemble-spec-package.sh",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sources": [
    { "skill": "discovery-agent", "schema": "../.claude/skills/discovery-agent/assets/discovery-state.schema.json", "produces": ["requirements/business-rules.md"] },
    { "skill": "prd-agent", "schema": "../.claude/skills/prd-agent/assets/prd-state.schema.json", "produces": ["product/prd.md", "product/personas.md"] },
    { "skill": "requirements-agent", "schema": "../.claude/skills/requirements-agent/assets/requirements-state.schema.json", "produces": ["requirements/functional.md", "requirements/non-functional.md"] },
    { "skill": "user-stories-agent", "schema": "../.claude/skills/user-stories-agent/assets/user-stories-state.schema.json", "produces": ["user-stories/*.md", "acceptance/acceptance-criteria.md"] },
    { "skill": "uml-agent", "schema": "../.claude/skills/uml-agent/assets/uml-state.schema.json", "produces": ["models/*.mmd"] },
    { "skill": "estimation-agent", "schema": "../.claude/skills/estimation-agent/assets/estimation-state.schema.json", "produces": ["estimation/estimate.md"] },
    { "skill": "proposal-agent", "schema": "../.claude/skills/proposal-agent/assets/proposal-state.schema.json", "produces": ["proposal/commercial-proposal.md"] }
  ],
  "not_backed": ["architecture/ -- fuera de alcance por diseño: arquitectura y modelo de datos son responsabilidad del SDD consumidor que reciba este spec package, nunca de este pipeline"],
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
