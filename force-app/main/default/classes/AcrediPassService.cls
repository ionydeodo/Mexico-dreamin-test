/**
 * HU-05: envía las inscripciones confirmadas a AcrediPass (POST {URL base}/registrations).
 *
 * La URL base y la API key viven en la Named Credential "AcrediPass" y su External Credential;
 * la key nunca está en el código ni en el repositorio. El header X-Api-Key lo agrega la plataforma.
 */
public without sharing class AcrediPassService implements Queueable, Database.AllowsCallouts {
    public static final String ENDPOINT = 'callout:AcrediPass/registrations';
    /** Recomendación del proveedor. */
    public static final Integer TIMEOUT_MS = 10000;
    /** Máximo de callouts por job (el límite de la plataforma es 100 y cada uno puede tardar 10 s). */
    @TestVisible
    private static final Integer BATCH_SIZE = 10;

    private final List<Id> registrationIds;

    public AcrediPassService(List<Id> registrationIds) {
        this.registrationIds = registrationIds;
    }

    /** Encola el envío; se llama desde el trigger cuando una inscripción queda Confirmada o se reintenta. */
    public static void enqueue(Set<Id> registrationIds) {
        if (registrationIds == null || registrationIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            System.debug(LoggingLevel.ERROR, 'DevSummit: sin capacidad para encolar el envío a AcrediPass: ' + registrationIds);
            markError(registrationIds, 'No se pudo encolar el envío. Usa "Reintentar envío a AcrediPass".');
            return;
        }
        System.enqueueJob(new AcrediPassService(new List<Id>(registrationIds)));
    }

    public void execute(QueueableContext ctx) {
        List<Id> current = new List<Id>();
        List<Id> remaining = new List<Id>();
        for (Integer i = 0; i < registrationIds.size(); i++) {
            (i < BATCH_SIZE ? current : remaining).add(registrationIds[i]);
        }

        // CA-05.4: solo confirmadas que aún no se enviaron con éxito.
        List<Registration__c> registrations = [
            SELECT
                Id, Attendee_Name__c, Attendee_Email__c, Company__c, Accreditation_Status__c,
                Session__r.Name, Session__r.Start__c
            FROM Registration__c
            WHERE
                Id IN :current
                AND Status__c = :DevSummit.REG_CONFIRMED
                AND Accreditation_Status__c != :DevSummit.ACC_SENT
                AND Accreditation_Id__c = NULL
        ];

        List<Registration__c> updates = new List<Registration__c>();
        for (Registration__c r : registrations) {
            updates.add(send(r));
        }
        if (!updates.isEmpty()) {
            for (Database.SaveResult sr : Database.update(updates, false)) {
                if (!sr.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'DevSummit: no se pudo guardar el resultado de AcrediPass: ' + sr.getErrors());
                }
            }
        }
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new AcrediPassService(remaining));
        }
    }

    /** Hace el callout y devuelve el registro con el resultado (CA-05.2 / CA-05.3). */
    @TestVisible
    private static Registration__c send(Registration__c r) {
        Registration__c result = new Registration__c(Id = r.Id);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(buildPayload(r)));
        try {
            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            String badgeId = code >= 200 && code < 300 ? parseBadgeId(res.getBody()) : null;
            if (String.isNotBlank(badgeId)) {
                result.Accreditation_Status__c = DevSummit.ACC_SENT;
                result.Accreditation_Id__c = badgeId.left(80);
                result.Accreditation_Error__c = null;
            } else {
                result.Accreditation_Status__c = DevSummit.ACC_ERROR;
                result.Accreditation_Error__c = ('HTTP ' + code + ': ' + (res.getBody() == null ? '' : res.getBody())).left(255);
            }
        } catch (Exception e) {
            // Timeout, credencial no configurada, etc.
            result.Accreditation_Status__c = DevSummit.ACC_ERROR;
            result.Accreditation_Error__c = (e.getTypeName() + ': ' + e.getMessage()).left(255);
        }
        return result;
    }

    @TestVisible
    private static Map<String, Object> buildPayload(Registration__c r) {
        return new Map<String, Object>{
            'externalId' => String.valueOf(r.Id),
            'fullName' => r.Attendee_Name__c,
            'email' => r.Attendee_Email__c,
            'company' => r.Company__c,
            'sessionTitle' => r.Session__r.Name,
            'sessionStart' => DevSummit.formatIsoMexicoCity(r.Session__r.Start__c)
        };
    }

    private static String parseBadgeId(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof Map<String, Object>) {
                Object badge = ((Map<String, Object>) parsed).get('badgeId');
                return badge == null ? null : String.valueOf(badge);
            }
        } catch (JSONException e) {
            System.debug(LoggingLevel.WARN, 'DevSummit: respuesta de AcrediPass no es JSON: ' + body);
        }
        return null;
    }

    private static void markError(Set<Id> ids, String message) {
        List<Registration__c> updates = new List<Registration__c>();
        for (Id i : ids) {
            updates.add(new Registration__c(Id = i, Accreditation_Status__c = DevSummit.ACC_ERROR, Accreditation_Error__c = message));
        }
        Database.update(updates, false);
    }
}
