# DevSummit CDMX — Registro a sesiones con cupo limitado

Implementación en Salesforce del diseño funcional *"Registro a sesiones con cupo limitado"*. Los asistentes buscan
talleres y se inscriben desde un sitio público (Experience Cloud, sin login). El equipo organizador aprueba las
inscripciones patrocinadas desde Salesforce, y las inscripciones confirmadas se envían a AcrediPass.

## Arquitectura

| Capa | Componentes |
| --- | --- |
| Datos | `Session__c` (Sesión) 1 → N `Registration__c` (Inscripción, master-detail). `Seats_Taken__c` (roll-up) y `Available_Seats__c` (fórmula) implementan RN-01 para mostrar cupos. |
| Reglas | `RegistrationTrigger` → `RegistrationTriggerHandler`, `SessionTrigger` → `SessionTriggerHandler`, `SessionCapacityService`. Las reglas aplican a cualquier canal: sitio, UI interna o API. |
| Sitio público | LWR "Build Your Own" (`site/`) con el LWC `devsummitApp` y sus componentes `dsSessionCard`, `dsRegistrationForm`, `dsMyRegistrations` y `dsUtils`. La API es `PublicSiteController`. |
| Organizador | App **DevSummit CDMX**, vista de lista *Pendientes de aprobación*, acciones rápidas **Aprobar**, **Rechazar** y **Reintentar envío a AcrediPass**. |
| Correos | Plantillas con la marca del evento (carpeta *DevSummit CDMX*) que combina `DevSummitEmailService`. El remitente y la lista de logística se configuran en el Custom Metadata `DevSummit_Setting__mdt`. |
| Integración | `AcrediPassService` (Queueable con callouts) usa la Named Credential `AcrediPass` y la External Credential `AcrediPass`, que agrega el header `X-Api-Key`. |

### Decisiones clave

- **Cero sobreventas con concurrencia (RN-01, RNF).** Cada inserción bloquea la fila de la sesión
  (`SELECT … FOR UPDATE`) antes de contar las inscripciones Confirmadas y Pendientes. Las transacciones que compiten
  por la misma sesión se forman en fila, y cada una ve las inscripciones que confirmaron las anteriores. Si el
  bloqueo tarda más de 10 s, el asistente ve "Hay mucha demanda en este momento…".
- **Una inscripción activa por email y sesión (CA-02.2).** Además de la validación, `Unique_Key__c`
  (sesión + email en minúsculas) es único en la base de datos. La llave se limpia al rechazar, porque las
  inscripciones rechazadas no cuentan.
- **El estado inicial lo decide el sistema (RN-02).** El trigger ignora cualquier estado que mande el canal.
- **Abierta/Llena es derivado (CA-06.2).** `SessionTriggerHandler` lo recalcula cuando cambia la capacidad o las
  inscripciones. El aviso a logística se envía solo en la transición a Llena (CA-06.3). *Cancelada* sí es manual.
- **Solo organizadores deciden (CA-04.5, RN-03).** La validación `Only_Organizers_Decide` usa el permiso
  personalizado `Approve_Registrations`, y `Status_Transition` impide salir de los estados finales.

### Seguridad del sitio público

- El usuario invitado **no tiene permisos sobre los objetos**. Todo pasa por `PublicSiteController`, que valida cada
  entrada, escribe solo una lista cerrada de campos y devuelve DTOs con los campos públicos.
- Nunca se exponen el contacto del speaker, el monto del patrocinio ni las notas internas. Hay pruebas que lo
  verifican.
- **El código de confirmación solo llega por correo**: no se muestra en la pantalla de éxito. Si se mostrara,
  cualquiera podría inscribirse con el email de otra persona y luego consultar todas sus inscripciones (HU-03).
- La consulta de "mis inscripciones" responde con un mensaje genérico, sin revelar si el email existe.
- Los datos que escribe el asistente se escapan antes de insertarlos en el HTML de los correos.
- **La API key de AcrediPass no está en el repositorio.** El diseño funcional la trae en texto plano, en la nota del
  proveedor. Esa key debe considerarse expuesta: pide a AcrediPass que la roten y guarda la nueva solo en la
  External Credential.
- El permission set del invitado incluye el principal de AcrediPass. Las inscripciones que se confirman al instante
  se envían desde la transacción del invitado, y el código nunca expone la key: la agrega la plataforma.

## Trazabilidad: criterio de aceptación → prueba

| Historia | Prueba Apex |
| --- | --- |
| HU-01 Buscar sesiones (CA-01.1 a 01.6) | `SessionCatalogTest` |
| HU-02 Inscribirme (CA-02.1 a 02.8, RN-04, RN-05) | `RegistrationTest`, `ConfirmationCodeGeneratorTest` |
| HU-03 Mis inscripciones (CA-03.1 a 03.3) | `MyRegistrationsTest` |
| HU-04 Aprobación (CA-04.1 a 04.5, RN-03) | `ApprovalTest` |
| HU-05 AcrediPass (CA-05.1 a 05.4) | `AcrediPassServiceTest` (con `AcrediPassCalloutMock`) |
| HU-06 Sesión llena (CA-06.1 a 06.3) | `SessionFullTest` |

Cada método se llama como su criterio, por ejemplo `ca02_3_neverExceedsCapacityCountingPending`. Resultado actual:
**todas las pruebas pasan, con 89 % de cobertura del org**.

## Puesta en marcha

Requisitos: [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) y un Dev Hub autenticado.

```bash
sf org login web --alias devhub --set-default-dev-hub
```

```bash
scripts/setup-scratch-org.sh devsummit devhub
```

El script crea el scratch org (si no existe), despliega `force-app`, asigna el permission set de organizador al
admin, crea y publica el sitio, activa el acceso de invitado, carga las seis sesiones de prueba (`data/`) y corre las
pruebas. Al final imprime la URL pública del sitio.

### Configurar AcrediPass

1. En **Setup → Named Credentials → AcrediPass**, cambia la URL base. El repositorio trae el marcador
   `https://webhook.site/REEMPLAZAR-POR-TU-ID`. Para probar, crea un endpoint en webhook.site que responda
   `201 {"badgeId": "BDG-48213"}`.
2. Guarda la key sin escribirla en ningún archivo:

   ```bash
   ACREDIPASS_API_KEY='la-key-nueva' scripts/set-acredipass-key.sh devsummit
   ```

3. Si un envío falla, la inscripción queda con estado de acreditación *Error* y aparece en la vista *Errores de
   acreditación*. Desde el registro, usa **Reintentar envío a AcrediPass**.

### Correos

- El remitente se muestra como "DevSummit CDMX", con respuesta a `no-reply@devsummit.example` (RN-07). Si creas y
  verificas una *Organization-Wide Email Address* con esa dirección, se usa automáticamente.
- Los orgs Developer y scratch tienen un límite diario bajo de correos. Si se alcanza, la inscripción se guarda igual
  y el error queda en el log.
- Para cambiar el remitente o la lista de logística, ve a **Setup → Custom Metadata Types → Configuración DevSummit**.

### Usuarios organizadores

Asigna el permission set **DevSummit - Organizador** (`DevSummit_Organizer`). Ese permission set incluye el permiso
de aprobación.

## Estructura

```
force-app/main/default/    metadata principal (objetos, Apex, LWC, permisos, correos, credenciales)
site/main/default/         sitio LWR (se despliega después de crear el sitio)
data/                      seis sesiones ficticias (sf data import tree)
scripts/                   setup del scratch org y carga de la key de AcrediPass
config/                    definición del scratch org (Experience Cloud habilitado, es_MX)
```

La metadata de `Network` y `CustomSite` no se versiona porque contiene usuarios y correos propios de cada org. El
script la genera y activa en cada scratch org.

## Fuera de alcance (según el diseño)

Pagos, cuentas de asistentes, cancelación por el asistente, lista de espera, Campaigns, app móvil y reportes. Tampoco
incluye protección anti-bots (captcha o límite de solicitudes) en el formulario público; se recomienda evaluarla
antes del evento.
