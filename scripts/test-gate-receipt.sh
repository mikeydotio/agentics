#!/usr/bin/env bash
# Adapt the full test entrypoint to the verifier's portable receipt contract.
# No supplied writer means ordinary local tests, without certification.
set -euo pipefail

case "${1:-}" in
    preflight|postlude) [ "$#" -eq 1 ] ;;
    *) printf 'test-gate: expected preflight or postlude\n' >&2; exit 2 ;;
esac

[ "${STORYHOOK_GATE_RECEIPT+x}" ] || exit 0
# Make 3.81 can emit separate -i words; newer Make also uses compact flags.
# Check both phases: -i can ignore even this preflight refusal. Arguments after
# -- are variable assignments, not options governing recipe failure handling.
read -r -a make_flags <<< "${MAKEFLAGS:-}"
for option in "${make_flags[@]:-}"; do
    case "$option" in
        --) break ;;
        --ignore-errors) ;;
        --*|*=*) continue ;;
        *i*) ;;
        *) continue ;;
    esac
    printf 'test-gate: ignore-errors cannot certify required tests\n' >&2
    exit 1
done
writer=$STORYHOOK_GATE_RECEIPT
case "$writer" in
    /*) ;;
    *) printf 'test-gate: STORYHOOK_GATE_RECEIPT must be an absolute executable path\n' >&2; exit 1 ;;
esac
if [ ! -f "$writer" ] || [ ! -x "$writer" ]; then
    printf 'test-gate: unusable STORYHOOK_GATE_RECEIPT: %s\n' "$writer" >&2
    exit 1
fi

if [ "$1" = preflight ]; then
    exec "$writer" preflight
fi
exec "$writer" postlude gate
