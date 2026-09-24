#!/usr/bin/env bash
# Deterministic pipeline-state checker for the Ingeniería de Requerimientos Agentica pipeline.
# Read-only: never writes, modifies, or deletes any state file.
set -euo pipefail

ROOT="${1:-$(pwd)}"

STAGES=(
  "discovery-agent:discovery-state.json"
  "prd-agent:prd-state.json"
  "requirements-agent:requirements-state.json"
  "user-stories-agent:user-stories-state.json"
  "uml-agent:uml-state.json"
  "estimation-agent:estimation-state.json"
  "proposal-agent:proposal-state.json"
)

mtime_of() {
  local f="$1"
  if stat -c %Y "$f" >/dev/null 2>&1; then
    stat -c %Y "$f"
  else
    stat -f %m "$f"
  fi
}

names=()
present=()
mtimes=()

for entry in "${STAGES[@]}"; do
  name="${entry%%:*}"
  file="${entry##*:}"
  names+=("$name")
  path="$ROOT/state/$file"
  if [ -f "$path" ]; then
    present+=("1")
    mtimes+=("$(mtime_of "$path")")
  else
    present+=("0")
    mtimes+=("0")
  fi
done

printf "%-22s | %-24s | %s\n" "Etapa" "Estado" "Nota"
printf "%-22s-+-%-24s-+-%s\n" "----------------------" "------------------------" "----------------------------------------"

next_missing=""
any_stale=0
count=${#STAGES[@]}

for ((i = 0; i < count; i++)); do
  name="${names[$i]}"
  st="present"
  note="-"

  if [ "${present[$i]}" = "0" ]; then
    st="missing"
    if [ -z "$next_missing" ]; then
      next_missing="$name"
    fi
  else
    if [ "$i" -gt 0 ] && [ "${present[$((i - 1))]}" = "1" ]; then
      upstream_mtime="${mtimes[$((i - 1))]}"
      this_mtime="${mtimes[$i]}"
      if [ "$upstream_mtime" -gt "$this_mtime" ]; then
        st="present, potentially stale"
        note="upstream (${names[$((i - 1))]}) cambió después de esta etapa"
        any_stale=1
      fi
    fi
  fi

  printf "%-22s | %-24s | %s\n" "$name" "$st" "$note"
done

echo ""
if [ -n "$next_missing" ]; then
  echo "Próximo paso: ejecutar $next_missing"
else
  echo "Pipeline completo"
fi

if [ "$any_stale" = "1" ]; then
  echo "Nota: hay etapas potencialmente desactualizadas respecto de su upstream. Esto es solo informativo -- la re-propagación automática todavía no está implementada (responsabilidad futura del Impact Analysis Agent, sección 18 del documento)."
fi

echo ""
echo "Definition of Ready:"
DOR_SCRIPT="$ROOT/.claude/skills/definition-of-ready-agent/scripts/check-definition-of-ready.sh"
if [ ! -f "$ROOT/state/user-stories-state.json" ]; then
  echo "  no evaluable todavía -- falta state/user-stories-state.json"
elif [ -f "$DOR_SCRIPT" ]; then
  DOR_OUTPUT=$(bash "$DOR_SCRIPT" "$ROOT" 2>&1 || true)
  DOR_VERDICT=$(printf '%s\n' "$DOR_OUTPUT" | grep "^VEREDICTO:" | sed 's/VEREDICTO: //')
  echo "  ${DOR_VERDICT:-desconocido} -- correr /definition-of-ready-agent para el detalle completo"
else
  echo "  script de definition-of-ready-agent no encontrado"
fi
