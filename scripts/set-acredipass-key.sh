#!/usr/bin/env bash
# Guarda la API key de AcrediPass como parámetro "ApiKey" del principal ApiKeyPrincipal de la
# External Credential "AcrediPass". La key se lee de la variable de entorno ACREDIPASS_API_KEY y
# nunca se escribe en el repositorio.
#
# Uso: ACREDIPASS_API_KEY=... scripts/set-acredipass-key.sh [alias]
# Para cambiar la URL base: Setup > Named Credentials > AcrediPass.
set -euo pipefail

ALIAS="${1:-devsummit}"
if [[ -z "${ACREDIPASS_API_KEY:-}" ]]; then
    echo "Define ACREDIPASS_API_KEY con la key que te dio AcrediPass." >&2
    exit 1
fi
if [[ ! "$ACREDIPASS_API_KEY" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "La key tiene caracteres inesperados." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/set-key.apex" <<APEX
ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
input.externalCredential = 'AcrediPass';
input.principalName = 'ApiKeyPrincipal';
input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
ConnectApi.CredentialValueInput key = new ConnectApi.CredentialValueInput();
key.value = '${ACREDIPASS_API_KEY}';
key.encrypted = true;
input.credentials = new Map<String, ConnectApi.CredentialValueInput>{ 'ApiKey' => key };
try {
    ConnectApi.NamedCredentials.createCredential(input);
} catch (ConnectApi.ConnectApiException e) {
    ConnectApi.NamedCredentials.updateCredential(input);
}
System.debug('AcrediPass: credencial guardada');
APEX
sf apex run -o "$ALIAS" -f "$TMP/set-key.apex" | grep -E "Compiled|Executed|AcrediPass|Error" || true
