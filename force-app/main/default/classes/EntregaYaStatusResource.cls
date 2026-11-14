/**
 * Endpoint que recibe los cambios de estado de EntregaYa (REQ-004).
 *
 *   POST /services/apexrest/entregaya/v1/status
 *   { "trackingNumber": "RC000001042", "status": "En reparto", "location": "Monterrey, NL",
 *     "timestamp": "2026-11-20T10:00:00-06:00", "proofId": null }
 *
 * Autenticación: OAuth 2.0 client credentials con un usuario de integración (ver README).
 * RN-04: además del acceso a la clase, el usuario debe tener el permiso personalizado
 * EntregaYa_Status_Update; cualquier otro usuario recibe 403.
 */
@RestResource(urlMapping='/entregaya/v1/status')
global without sharing class EntregaYaStatusResource {
    public static final String PERMISSION = 'EntregaYa_Status_Update';
    static final Pattern TRACKING_PATTERN = Pattern.compile('^RC\\d{9}$');

    public class StatusUpdate {
        public String trackingNumber;
        public String status;
        public String location;
        public String timestamp;
        public String proofId;
    }

    @HttpPost
    global static void receive() {
        RestResponse res = RestContext.response;
        Map<String, Object> out;
        Integer code;
        try {
            out = process(RestContext.request.requestBody == null ? null : RestContext.request.requestBody.toString());
            code = 200;
        } catch (StatusException e) {
            code = e.httpStatus;
            out = new Map<String, Object>{ 'result' => 'rejected', 'errorCode' => e.errorCode, 'message' => e.getMessage() };
        }
        res.statusCode = code;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }

    @TestVisible
    static Map<String, Object> process(String rawBody) {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw fail(403, 'FORBIDDEN', 'Solo EntregaYa puede enviar actualizaciones de estado.');
        }
        StatusUpdate u = parse(rawBody);

        String tn = u.trackingNumber == null ? '' : u.trackingNumber.trim().toUpperCase();
        if (!TRACKING_PATTERN.matcher(tn).matches()) {
            throw fail(400, 'INVALID_TRACKING_NUMBER', 'trackingNumber debe ser RC seguido de 9 dígitos.');
        }
        String status = canonicalStatus(u.status);
        if (status == null) {
            throw fail(
                400,
                'INVALID_STATUS',
                'status no es válido. Valores permitidos: ' + String.join(new List<String>(validStatuses()), ', ') + '.'
            );
        }
        Datetime ts = parseTimestamp(u.timestamp);
        if (ts == null) {
            throw fail(400, 'INVALID_TIMESTAMP', 'timestamp es obligatorio en formato ISO 8601, p. ej. 2026-11-20T10:00:00-06:00.');
        }

        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Last_Update__c
            FROM Shipment__c
            WHERE Name = :tn
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw fail(404, 'TRACKING_NOT_FOUND', 'No existe un envío con el número de guía ' + tn + '.');
        }
        Shipment__c s = rows[0];

        // CA-004.4: una actualización más antigua que la última registrada se ignora.
        if (s.Last_Update__c != null && ts < s.Last_Update__c) {
            return new Map<String, Object>{
                'result' => 'ignored',
                'trackingNumber' => tn,
                'message' => 'La actualización es más antigua que la última registrada.'
            };
        }

        s.Status__c = status;
        s.Last_Location__c = String.isBlank(u.location) ? s.Last_Location__c : u.location.trim().left(255);
        s.Last_Update__c = ts;
        if (status == ShipmentTrackingController.STATUS_DELIVERED) {
            s.Delivered_At__c = ts;
            if (String.isNotBlank(u.proofId)) {
                s.Proof_Id__c = u.proofId.trim().left(80);
            }
        }
        update s;

        return new Map<String, Object>{ 'result' => 'updated', 'trackingNumber' => tn, 'status' => status };
    }

    static StatusUpdate parse(String rawBody) {
        if (String.isBlank(rawBody)) {
            throw fail(400, 'INVALID_REQUEST', 'El cuerpo de la petición está vacío.');
        }
        try {
            return (StatusUpdate) JSON.deserialize(rawBody, StatusUpdate.class);
        } catch (Exception e) {
            throw fail(400, 'INVALID_REQUEST', 'El cuerpo de la petición no es un JSON válido.');
        }
    }

    static Set<String> validStatuses() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry e : Shipment__c.Status__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                values.add(e.getValue());
            }
        }
        return values;
    }

    static String canonicalStatus(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (String v : validStatuses()) {
            if (v.equalsIgnoreCase(value.trim())) {
                return v;
            }
        }
        return null;
    }

    @TestVisible
    static Datetime parseTimestamp(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + value.trim() + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    static StatusException fail(Integer httpStatus, String errorCode, String message) {
        StatusException e = new StatusException(message);
        e.httpStatus = httpStatus;
        e.errorCode = errorCode;
        return e;
    }

    public class StatusException extends Exception {
        public Integer httpStatus;
        public String errorCode;
    }
}
