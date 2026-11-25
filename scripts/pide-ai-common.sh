#!/usr/bin/env bash
# Sourced after common.sh by the installer, MCP launcher and doctor.

PIDE_AI_REVISION=6618654fc847f2996972e8dd8c546a57d704fb84
PIDE_AI_DIR="$TOOLING_ROOT/.pide-ai/$PIDE_AI_REVISION"

pide_ai_checkout_ok() {
  [[ -f "$PIDE_AI_DIR/etc/components" ]] &&
    [[ "$(git -C "$PIDE_AI_DIR" rev-parse HEAD 2>/dev/null)" == "$PIDE_AI_REVISION" ]] &&
    git -C "$PIDE_AI_DIR" diff --quiet HEAD --
}

# A read-only check. Running the Isabelle tool itself can compile Scala.
pide_ai_ready() {
  pide_ai_checkout_ok ||
    die "PIDE AI source is missing or differs from $PIDE_AI_REVISION. Run $TOOLING_ROOT/scripts/setup-pide-ai.sh."
  local ai_home mcp_home symbols_home
  ai_home="$("$ISABELLE_CMD" getenv -b PIDE_AI_HOME)" || die "Cannot read PIDE_AI_HOME from Isabelle2026."
  mcp_home="$("$ISABELLE_CMD" getenv -b PIDE_MCP_HOME)" || die "Cannot read PIDE_MCP_HOME from Isabelle2026."
  symbols_home="$("$ISABELLE_CMD" getenv -b SYMBOLS_HOME)" || die "Cannot read SYMBOLS_HOME from Isabelle2026."
  [[ "$ai_home" == "$PIDE_AI_DIR/AI" && "$mcp_home" == "$PIDE_AI_DIR/MCP" &&
     "$symbols_home" == "$PIDE_AI_DIR/Symbols" ]] ||
    die "Isabelle2026 is not using the pinned PIDE AI component. Run $TOOLING_ROOT/scripts/setup-pide-ai.sh."
  [[ -f "$ai_home/lib/isabelle_pide_ai.jar" && -f "$mcp_home/lib/isabelle_pide_mcp.jar" &&
     -f "$symbols_home/lib/symbols.jar" ]] ||
    die "PIDE AI JARs are missing. Run $TOOLING_ROOT/scripts/setup-pide-ai.sh."
}
