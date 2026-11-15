#!/usr/bin/env bash
# Guarda la API key de EntregaYa en el principal "EntregaYaApi" de la External Credential "EntregaYa".
# La key nunca va al repositorio: se lee de la variable de entorno ENTREGAYA_API_KEY.
# Con el mock (mock/entregaya) cualquier valor sirve, porque el mock no valida la key.
#   ENTREGAYA_API_KEY=<key> ./scripts/set-entregaya-api-key.sh [alias]
set -euo pipefail
: "${ENTREGAYA_API_KEY:?Define ENTREGAYA_API_KEY con la API key de EntregaYa}"
ORG="${1:-}"
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
node -e 'process.stdout.write(JSON.stringify({externalCredential:"EntregaYa",principalName:"EntregaYaApi",principalType:"NamedPrincipal",credentials:{ApiKey:{value:process.env.ENTREGAYA_API_KEY,encrypted:true}}}))' > "$BODY_FILE"
API="/services/data/v64.0/named-credentials/credential"
# POST crea la credencial; si ya existe, PUT la reemplaza.
if ! sf api request rest "$API" --method POST --header "Content-Type:application/json" --body "@$BODY_FILE" ${ORG:+--target-org "$ORG"} >/dev/null 2>&1; then
  sf api request rest "$API" --method PUT --header "Content-Type:application/json" --body "@$BODY_FILE" ${ORG:+--target-org "$ORG"} >/dev/null
fi
echo "API key guardada en la External Credential EntregaYa (principal EntregaYaApi)."
