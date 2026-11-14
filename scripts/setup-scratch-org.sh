#!/usr/bin/env bash
# Crea un scratch org con todo el proyecto RutaCargo listo para probar.
# Requisito: un Dev Hub autorizado como default (sf org login web --set-default-dev-hub).
#   ./scripts/setup-scratch-org.sh [alias] [días]
set -euo pipefail
cd "$(dirname "$0")/.."

ALIAS="${1:-rutacargo}"
DAYS="${2:-7}"
SITE_NAME="Rastreo RutaCargo"

echo "==> Creando scratch org '$ALIAS' ($DAYS días)"
sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" \
  --set-default --duration-days "$DAYS" --wait 15

echo "==> Desplegando metadata"
sf project deploy start --target-org "$ALIAS" --wait 30

echo "==> Asignando permisos al administrador (agente + simulador de EntregaYa)"
sf org assign permset --name RutaCargo_Agent --name RutaCargo_EntregaYa_Integration --target-org "$ALIAS"

echo "==> Cargando datos de prueba"
sf apex run --file scripts/apex/seed-data.apex --target-org "$ALIAS" | grep -E 'USER_DEBUG|Error|error' || true

echo "==> Creando el sitio de Experience Cloud '$SITE_NAME'"
sf community create --name "$SITE_NAME" --template-name "Build Your Own (LWR)" \
  --url-path-prefix rastreo --description "Rastreo público de envíos RutaCargo" --target-org "$ALIAS"

echo "==> Esperando al usuario invitado del sitio"
for i in $(seq 1 30); do
  n=$(sf data query --target-org "$ALIAS" --json \
      --query "SELECT COUNT() FROM User WHERE UserType = 'Guest' AND Profile.Name LIKE 'Rastreo RutaCargo%'" \
      | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).result.totalSize))')
  [ "$n" -gt 0 ] && break
  sleep 10
done
sf apex run --file scripts/apex/assign-guest-permset.apex --target-org "$ALIAS" | grep -E 'USER_DEBUG|Error' || true

echo "==> Ejecutando pruebas Apex"
sf apex run test --target-org "$ALIAS" --test-level RunLocalTests --code-coverage --result-format human --wait 20

echo
echo "Listo. Pasos manuales pendientes: ver README.md, sección 'Pasos manuales'."
sf org open --target-org "$ALIAS" --path "/lightning/o/Shipment__c/list" --url-only
