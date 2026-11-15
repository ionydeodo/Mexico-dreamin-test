# RutaCargo — Rastreo público de envíos

Implementación en Salesforce del documento *Diseño funcional — Rastreo público de envíos RutaCargo*:
sitio público de Experience Cloud (sin login) para rastrear envíos, ver el detalle de entrega,
descargar el comprobante y reprogramar, más el endpoint que recibe los estados de EntregaYa.

## Qué incluye

| Pieza | Archivo(s) | Requisitos |
| --- | --- | --- |
| Objeto `Shipment__c` (Envío) y campos de `Account` | `force-app/main/default/objects` | Modelo de datos, RN-05 |
| Controlador del sitio | `classes/ShipmentTrackingController.cls` | REQ-001, REQ-002, REQ-003, RN-01/02/03/06 |
| Cliente de comprobantes EntregaYa | `classes/EntregaYaProofService.cls` | CA-002.4, CA-002.5 |
| Endpoint de estados `POST /services/apexrest/entregaya/v1/status` | `classes/EntregaYaStatusResource.cls` | REQ-004, RN-04 |
| Componente LWC del sitio (móvil primero) | `lwc/rutaCargoTracker` | REQ-001 a REQ-003 |
| Named/External Credential `EntregaYa` | `namedCredentials`, `externalCredentials` | Integración |
| Permission sets | `permissionsets` | Invitado, integración, agente |
| Pruebas Apex (una o más por criterio de aceptación) | `classes/*Test.cls` | DoD |
| Datos de prueba reproducibles | `scripts/apex/seed-data.apex` | DoD |

## Crear el scratch org

Requisitos: [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) y un Dev Hub autorizado.

```bash
sf org login web --set-default-dev-hub --alias DevHub   # una sola vez
./scripts/setup-scratch-org.sh rutacargo 7
```

El script crea el org, despliega la metadata, asigna permisos, carga los 120 envíos de prueba,
crea el sitio **Rastreo RutaCargo** (`/rastreo`, plantilla Build Your Own LWR), asigna el permission set
al usuario invitado, coloca el componente en la Home, activa el acceso público, publica el sitio y corre
las pruebas Apex con cobertura. La metadata del sitio vive en `site/` y se despliega después de crearlo.

## Pasos manuales

Estos pasos dependen de datos que no van en el repositorio (secretos del proveedor) y quedan pendientes:

1. **Ambiente real de EntregaYa** (opcional; por defecto se usa el mock, ver abajo):
   - Named Credential *EntregaYa*: cambia la URL por la URL base del proveedor.
   - Guarda la API key real: `ENTREGAYA_API_KEY=<key> ./scripts/set-entregaya-api-key.sh rutacargo`.
     **No la guardes en el repositorio.**
2. **Usuario de integración de EntregaYa (OAuth 2.0 client credentials).**
   - Crea un usuario de integración (licencia *Salesforce Integration*, perfil *Minimum Access - API Only
     Integrations*) y asígnale **RutaCargo - Integración EntregaYa**.
   - Crea una External Client App (o Connected App) con OAuth habilitado, flujo *Client Credentials*,
     scope `api`, y como *Run As* el usuario de integración.
   - Entrega a EntregaYa: URL del token `https://<mi-dominio>.my.salesforce.com/services/oauth2/token`,
     client id/secret, y la URL del servicio
     `https://<mi-dominio>.my.salesforce.com/services/apexrest/entregaya/v1/status`.

## Probar

**Sitio:** abre la URL del sitio (Setup → Digital Experiences) desde el celular o en modo incógnito.
Las guías van de `RC000001001` a `RC000001120`; las referencias son `ACME-2026001…` y `GLX-2026001…`.
Para abrir un detalle necesitas el código postal de destino:

```bash
sf data query -q "SELECT Name, Status__c, Destination_Postal_Code__c FROM Shipment__c ORDER BY Name LIMIT 10"
```

**EntregaYa simulado:**

```bash
./scripts/simulate-entregaya.sh RC000001002 "En reparto" "Monterrey, NL"
./scripts/simulate-entregaya.sh RC000001002 "Entregado" "Monterrey, NL" PRF-99999
```

Respuestas: `200 {"result":"updated"}`, `200 {"result":"ignored"}` (actualización más antigua, CA-004.4),
`400` con `errorCode` `INVALID_STATUS` / `INVALID_TRACKING_NUMBER` / `INVALID_TIMESTAMP` / `INVALID_REQUEST`,
`404 TRACKING_NOT_FOUND`, `403 FORBIDDEN` si el usuario no es EntregaYa (RN-04).

**Pruebas Apex:** `sf apex run test --test-level RunLocalTests --code-coverage --result-format human`

## Mock de EntregaYa (comprobantes)

La Named Credential *EntregaYa* apunta a un mock estático versionado en el repo: `mock/entregaya/proofs/<proofId>`
contiene el JSON que documenta el proveedor (`proofId`, `trackingNumber`, `signedBy`, `fileName`, `pdfBase64`)
para los 24 envíos Entregados del seed, y se sirve por jsDelivr fijado a un commit:
`https://cdn.jsdelivr.net/gh/ionydeodo/mexico-dreamin-test@<commit>/mock/entregaya`.

- Un comprobante inexistente responde 404, así que el sitio muestra "No pudimos obtener el comprobante…".
- El mock **no valida la API key**. No se pudo hospedar dentro de Salesforce porque un Apex REST público
  rechaza cualquier header `Authorization: Bearer` ajeno con 401 `INVALID_SESSION_ID`.
- Para regenerarlo: `python3 scripts/mock/generate-entregaya-proofs.py delivered.csv` (instrucciones en el script),
  hacer commit y actualizar el commit en la URL de la Named Credential.
- El usuario invitado necesita lectura sobre *User External Credential* (ya incluida en
  `RutaCargo_Guest_Site`): Salesforce la exige para cualquier callout con External Credential.

## Decisiones de diseño

- **Seguridad del sitio.** El usuario invitado no tiene acceso a ningún objeto. Todo pasa por
  `ShipmentTrackingController` (`without sharing`), que solo devuelve DTOs con los campos permitidos:
  el rastreo, los de CA-001.2 (RN-01); el detalle, comprobante y reprogramación exigen el código postal
  en **cada** llamada (RN-02); nunca se exponen precio, costo, margen, notas ni datos del remitente (RN-03).
  Las pruebas verifican que esos datos no aparecen en las respuestas.
- **Mismo mensaje para guía inexistente y código postal incorrecto**, para no revelar qué guías existen.
- **CA-003.2.** Se interpretó *"entre el día siguiente y 7 días naturales después de la fecha estimada
  original"* como: mínimo mañana (hora de CDMX), máximo la fecha estimada original + 7. La fecha original
  se guarda en `Original_Estimated_Delivery__c` en la primera reprogramación, así el límite no se recorre.
- **CA-003.5.** El historial de campos registra fecha estimada, instrucciones, contador y estado; el agente
  lo ve en la lista relacionada *Historial* del envío.
- **Número de guía** = Auto Number `RC{000000000}` iniciando en 1001 (RN-05).
- **Comprobante.** El PDF va de EntregaYa al navegador en base64; no se guarda en Salesforce. Timeout de
  10 s. Además se valida que el comprobante corresponda a la guía consultada.
- **CA-004.4.** Una actualización con `timestamp` anterior al `Last_Update__c` se ignora (respuesta 200
  `ignored`, para que EntregaYa no reintente). Una con el mismo timestamp se aplica (idempotente).

## Pendientes / riesgos conocidos

- El código postal es un factor débil (5 dígitos). Para producción conviene limitar intentos por guía
  o agregar un CAPTCHA en el sitio.
- La API key de prueba aparece en el ticket del proveedor dentro del documento funcional; conviene
  pedir a EntregaYa que la rote antes de producción.
