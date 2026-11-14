#!/usr/bin/env bash
# Simula a EntregaYa enviando un cambio de estado (REQ-004).
#   ./scripts/simulate-entregaya.sh RC000001002 "En reparto" "Monterrey, NL" [proofId] [timestamp]
# Usa el usuario por defecto del CLI, que el script de setup deja con el permission set
# RutaCargo_EntregaYa_Integration. En producción la llamada la hace EntregaYa con OAuth 2.0
# client credentials (ver README).
set -euo pipefail
TRACKING="${1:?Número de guía}"
STATUS="${2:?Estado}"
LOCATION="${3:-}"
PROOF="${4:-}"
TS="${5:-$(TZ=America/Mexico_City date +%Y-%m-%dT%H:%M:%S%:z)}"
BODY=$(node -e 'const [t,s,l,p,ts]=process.argv.slice(1);console.log(JSON.stringify({trackingNumber:t,status:s,location:l||null,timestamp:ts,proofId:p||null}))' \
  "$TRACKING" "$STATUS" "$LOCATION" "$PROOF" "$TS")
echo "POST /services/apexrest/entregaya/v1/status  $BODY"
printf '%s' "$BODY" > /tmp/entregaya-body.json
sf api request rest /services/apexrest/entregaya/v1/status --method POST \
  --header "Content-Type:application/json" --body /tmp/entregaya-body.json "${@:6}"
echo
