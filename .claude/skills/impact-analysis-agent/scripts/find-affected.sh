#!/usr/bin/env bash
# Deterministic transitive-impact tracer for the Ingeniería de Requerimientos Agentica pipeline.
# Read-only: never writes, modifies, or deletes any state file.
# Usage: find-affected.sh <id-o-palabra-clave>   (ej: RN-03, RF-04, HU-02)
set -uo pipefail

SEED="${1:-}"
if [ -z "$SEED" ]; then
  echo "Uso: find-affected.sh <id-o-palabra-clave>  (ej: RN-03, RF-04, HU-02)" >&2
  exit 1
fi

ROOT="$(pwd)"
STAGES="prd-state.json requirements-state.json user-stories-state.json uml-state.json estimation-state.json proposal-state.json"

label_for() {
  case "$1" in
    prd-state.json) echo "PRD" ;;
    requirements-state.json) echo "Requirements" ;;
    user-stories-state.json) echo "User Stories" ;;
    uml-state.json) echo "UML" ;;
    estimation-state.json) echo "Estimation" ;;
    proposal-state.json) echo "Proposal" ;;
    *) echo "$1" ;;
  esac
}

# Prints every top-level-array record (brace-depth 2->1) whose raw text contains $2, from file $1.
# Records are separated by a single 0x01 byte (never appears in JSON text).
extract_matching_records() {
  local file="$1" term="$2"
  [ -f "$file" ] || return 0
  awk -v term="$term" '
    BEGIN { depth = 0; buf = "" }
    {
      buf = buf $0 "\n"
      line = $0
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "{") { depth++ }
        else if (c == "}") {
          depth--
          if (depth == 1) {
            if (index(buf, term) > 0) { printf "%s\x01", buf }
            buf = ""
          }
        }
      }
    }
  ' "$file"
}

# Picks the best human-readable identifier out of a matched record block.
identify() {
  local block="$1" v
  v=$(printf '%s' "$block" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  if [ -n "$v" ]; then echo "$v"; return; fi
  v=$(printf '%s' "$block" | grep -oE '"item"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  if [ -n "$v" ]; then echo "$v"; return; fi
  v=$(printf '%s' "$block" | grep -oE '"file"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  if [ -n "$v" ]; then echo "$v"; return; fi
  v=$(printf '%s' "$block" | grep -oE '"source"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  if [ -n "$v" ]; then echo "entrada asociada a $v"; return; fi
  v=$(printf '%s' "$block" | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
  if [ -n "$v" ]; then echo "entrada tipo $v"; return; fi
  echo "(sin identificador claro)"
}

# Returns ONLY a record's own declared "id" (e.g. HU-04), never other ids it merely
# references (e.g. a diagram's "sources": ["RF-01","RF-02",...] array). Propagating
# co-referenced siblings instead of the record's own identity is what causes false
# fan-out: a diagram touching 6 stories is not "6 stories affecting each other".
own_id_of_block() {
  printf '%s' "$1" | grep -oE '"id"[[:space:]]*:[[:space:]]*"(RN|RNF|RF|HU)-[0-9]+"' | head -1 | sed -E 's/.*"((RN|RNF|RF|HU)-[0-9]+)"$/\1/'
}

frontier="$SEED"
searched=" $SEED "

# One accumulator variable per stage file (bash 3-compatible: no associative arrays).
hits_prd=""; hits_req=""; hits_us=""; hits_uml=""; hits_est=""; hits_prop=""

get_hits() {
  case "$1" in
    prd-state.json) echo "$hits_prd" ;;
    requirements-state.json) echo "$hits_req" ;;
    user-stories-state.json) echo "$hits_us" ;;
    uml-state.json) echo "$hits_uml" ;;
    estimation-state.json) echo "$hits_est" ;;
    proposal-state.json) echo "$hits_prop" ;;
  esac
}

append_hit() {
  local file="$1" line="$2" prev
  prev="$(get_hits "$file")"
  case "$prev" in
    *"$line"*) return ;;
  esac
  case "$file" in
    prd-state.json) hits_prd="${prev}${prev:+$'\n'}${line}" ;;
    requirements-state.json) hits_req="${prev}${prev:+$'\n'}${line}" ;;
    user-stories-state.json) hits_us="${prev}${prev:+$'\n'}${line}" ;;
    uml-state.json) hits_uml="${prev}${prev:+$'\n'}${line}" ;;
    estimation-state.json) hits_est="${prev}${prev:+$'\n'}${line}" ;;
    proposal-state.json) hits_prop="${prev}${prev:+$'\n'}${line}" ;;
  esac
}

pass=0
while [ -n "$frontier" ] && [ "$pass" -lt 6 ]; do
  pass=$((pass + 1))
  new_terms=""
  for term in $frontier; do
    for file in $STAGES; do
      raw="$(extract_matching_records "$ROOT/state/$file" "$term")"
      if [ -z "$raw" ]; then continue; fi
      set -f
      IFS=$'\x01'
      for rec in $raw; do
        if [ -z "$rec" ]; then continue; fi
        ident="$(identify "$rec")"
        append_hit "$file" "$ident (via $term)"
        nid="$(own_id_of_block "$rec")"
        if [ -n "$nid" ]; then
          case "$searched" in
            *" $nid "*) : ;;
            *) new_terms="$new_terms $nid"; searched="$searched $nid " ;;
          esac
        fi
      done
      set +f
      unset IFS
    done
  done
  frontier="$new_terms"
done

echo "Trazando impacto de: $SEED"
echo ""
any=0
for file in $STAGES; do
  label="$(label_for "$file")"
  echo "${label}:"
  hits="$(get_hits "$file")"
  if [ -z "$hits" ]; then
    echo "  (sin coincidencias)"
  else
    any=1
    printf '%s\n' "$hits" | sed 's/^/  - /'
  fi
  echo ""
done

if [ "$any" -eq 0 ]; then
  echo "Ningún artefacto downstream referencia a $SEED todavía."
fi
