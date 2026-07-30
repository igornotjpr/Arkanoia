#!/usr/bin/env bash
# Roda a suite de testes do Arkanoia.
#
#   ./scripts/test.sh          suite headless da camada pura
#   ./scripts/test.sh --all    suite pura + autoteste de integracao
#
# Defina GODOT para apontar para outro binario, se necessario.

set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "$GODOT" ]]; then
	echo "Binario do Godot nao encontrado em: $GODOT" >&2
	echo "Defina a variavel GODOT com o caminho correto." >&2
	exit 1
fi

# Reimporta para atualizar o cache de classes globais (necessario apos criar ou
# renomear um script com class_name).
echo ">> importando projeto"
"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true

echo ">> suite da camada pura"
"$GODOT" --headless --path "$PROJECT_DIR" --script res://tests/run_tests.gd

if [[ "${1:-}" == "--all" ]]; then
	# Sem --fixed-fps de proposito. O timeout do HTTPRequest conta tempo de
	# processamento: com o relogio acelerado, os 8s de timeout passariam em ~0,1s
	# reais e a requisicao ao Supabase morreria antes de qualquer resposta. Em
	# tempo real, o autoteste valida de verdade o caminho HTTP (leva ~30s).
	echo ">> autoteste de integracao (tempo real, ~30s)"
	"$GODOT" --headless --path "$PROJECT_DIR" -- --arkanoia-selftest
fi
