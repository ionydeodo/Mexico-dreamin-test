#!/usr/bin/env bash
# Prepara un scratch org completo para DevSummit CDMX:
#   metadata, sitio público de Experience Cloud, permisos, datos de prueba y pruebas Apex.
#
# Uso:
#   scripts/setup-scratch-org.sh [alias] [dev-hub]
#     alias    alias del scratch org (default: devsummit). Si no existe, se crea.
#     dev-hub  alias del Dev Hub (default: el Dev Hub por defecto de la CLI)
#
# Opcional: export ACREDIPASS_API_KEY=... para guardar la key de AcrediPass en el org.
set -euo pipefail

ALIAS="${1:-devsummit}"
DEV_HUB="${2:-}"
SITE_NAME="DevSummit CDMX"
SITE_PREFIX="devsummit"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

if ! sf org display -o "$ALIAS" >/dev/null 2>&1; then
    step "Creando scratch org '$ALIAS'"
    HUB_ARG=()
    [[ -n "$DEV_HUB" ]] && HUB_ARG=(-v "$DEV_HUB")
    sf org create scratch -f config/project-scratch-def.json -a "$ALIAS" -d -y 30 -w 30 "${HUB_ARG[@]}"
fi

step "Desplegando metadata (force-app)"
sf project deploy start -d force-app -o "$ALIAS" -w 30

step "Asignando el permission set de organizador al usuario admin"
sf org assign permset -n DevSummit_Organizer -o "$ALIAS" || true

step "Creando el sitio '$SITE_NAME' (si no existe)"
SITE_COUNT=$(sf data query -o "$ALIAS" --json -q "SELECT COUNT() FROM Network WHERE Name = '$SITE_NAME'" | node -pe 'JSON.parse(require("fs").readFileSync(0)).result.totalSize')
if [[ "$SITE_COUNT" == "0" ]]; then
    JOB=$(sf community create -o "$ALIAS" --json --name "$SITE_NAME" --template-name "Build Your Own (LWR)" \
        --url-path-prefix "$SITE_PREFIX" --description "Inscripción pública a talleres de DevSummit CDMX" |
        node -pe 'JSON.parse(require("fs").readFileSync(0)).result.jobId')
    for _ in $(seq 1 60); do
        STATUS=$(sf data query -o "$ALIAS" --json -q "SELECT Status FROM BackgroundOperation WHERE Id = '$JOB'" |
            node -pe 'JSON.parse(require("fs").readFileSync(0)).result.records[0].Status')
        [[ "$STATUS" == "Complete" ]] && break
        [[ "$STATUS" == "Error" ]] && { echo "La creación del sitio falló"; exit 1; }
        sleep 5
    done
fi

step "Desplegando el sitio (página de inicio con el componente y acceso público)"
sf project deploy start -d site -o "$ALIAS" -w 30

step "Activando el sitio"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sf project retrieve start -m "Network:$SITE_NAME" -o "$ALIAS" --target-metadata-dir "$TMP" --unzip -w 10 >/dev/null
NETWORK_FILE="$(find "$TMP" -name '*.network' | head -1)"
sed -i.bak 's#<status>UnderConstruction</status>#<status>Live</status>#' "$NETWORK_FILE"
rm -f "$NETWORK_FILE.bak"
sf project deploy start --metadata-dir "$(dirname "$(dirname "$NETWORK_FILE")")" -o "$ALIAS" -w 10 >/dev/null

step "Asignando el permission set del invitado al usuario invitado del sitio"
GUEST_ID=$(sf data query -o "$ALIAS" --json \
    -q "SELECT GuestUserId FROM Site WHERE Name = 'DevSummit_CDMX' LIMIT 1" |
    node -pe 'const r=JSON.parse(require("fs").readFileSync(0)).result.records; r.length && r[0].GuestUserId ? r[0].GuestUserId : ""')
if [[ -n "$GUEST_ID" ]]; then
    PS_ID=$(sf data query -o "$ALIAS" --json -q "SELECT Id FROM PermissionSet WHERE Name = 'DevSummit_Site_Guest'" |
        node -pe 'JSON.parse(require("fs").readFileSync(0)).result.records[0].Id')
    sf data create record -o "$ALIAS" -s PermissionSetAssignment -v "AssigneeId=$GUEST_ID PermissionSetId=$PS_ID" >/dev/null 2>&1 ||
        echo "  (ya estaba asignado)"
else
    echo "  No encontré el usuario invitado; asígnalo a mano desde Experience Builder > Configuración > General."
fi

step "Publicando el sitio"
sf community publish -n "$SITE_NAME" -o "$ALIAS" >/dev/null

if [[ -n "${ACREDIPASS_API_KEY:-}" ]]; then
    step "Guardando la API key de AcrediPass en la External Credential"
    "$ROOT/scripts/set-acredipass-key.sh" "$ALIAS"
fi

step "Cargando las seis sesiones de prueba"
EXISTING=$(sf data query -o "$ALIAS" --json -q "SELECT COUNT() FROM Session__c" | node -pe 'JSON.parse(require("fs").readFileSync(0)).result.totalSize')
if [[ "$EXISTING" == "0" ]]; then
    sf data import tree -p data/sample-data-plan.json -o "$ALIAS"
else
    echo "  Ya hay $EXISTING sesiones; no se cargan de nuevo."
fi

step "Ejecutando las pruebas Apex"
sf apex run test -o "$ALIAS" -l RunLocalTests -c -w 30 -r human | grep -E "Outcome|Pass Rate|Org Wide Coverage|Tests Ran" || true

SITE_URL=$(sf data query -o "$ALIAS" --json \
    -q "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE PathPrefix = '/$SITE_PREFIX'" 2>/dev/null |
    node -pe 'const r=JSON.parse(require("fs").readFileSync(0)).result.records; r.length ? "https://" + r[0].Domain.Domain + r[0].PathPrefix : ""' 2>/dev/null || true)
step "Listo"
echo "  Sitio público: ${SITE_URL:-(ver Setup > Todos los sitios)}"
echo "  Abrir el org:  sf org open -o $ALIAS"
