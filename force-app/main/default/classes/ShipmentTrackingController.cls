/**
 * Controlador del sitio público de rastreo (REQ-001, REQ-002, REQ-003).
 *
 * El usuario invitado del sitio NO tiene acceso a Shipment__c ni a Account: toda la
 * lectura y escritura pasa por esta clase, que corre "without sharing" y aplica las
 * reglas de negocio de forma explícita:
 *  - RN-01: el rastreo solo devuelve los campos públicos de CA-001.2 (TrackingResult).
 *  - RN-02: los datos personales, el comprobante y la reprogramación exigen el código
 *           postal de destino, y se vuelve a verificar en CADA llamada.
 *  - RN-03: ningún DTO expone precio, costo, margen, notas internas ni datos del remitente.
 *  - RN-06: las fechas y horas se formatean en hora de Ciudad de México.
 */
public without sharing class ShipmentTrackingController {
    public static final Integer MAX_VALUES = 10;
    public static final Integer MAX_RESCHEDULES = 2;
    public static final Integer MAX_DAYS_AFTER_ORIGINAL = 7;
    public static final String TIMEZONE = 'America/Mexico_City';

    public static final String MODE_TRACKING = 'trackingNumber';
    public static final String MODE_REFERENCE = 'reference';

    public static final String STATUS_COLLECTED = 'Recolectado';
    public static final String STATUS_IN_TRANSIT = 'En tránsito';
    public static final String STATUS_OUT_FOR_DELIVERY = 'En reparto';
    public static final String STATUS_DELIVERED = 'Entregado';
    public static final String STATUS_INCIDENT = 'Incidencia';
    public static final Set<String> RESCHEDULABLE_STATUSES = new Set<String>{ STATUS_COLLECTED, STATUS_IN_TRANSIT };

    public static final String MSG_NOT_FOUND = 'No encontrado';
    public static final String MSG_DATA_MISMATCH = 'Los datos no coinciden con este envío';
    public static final String MSG_PROOF_UNAVAILABLE = 'No pudimos obtener el comprobante, intenta más tarde';
    public static final String MSG_TOO_MANY_VALUES = 'Puedes buscar hasta ' + MAX_VALUES + ' valores a la vez.';
    public static final String MSG_NO_VALUES = 'Ingresa al menos un número de guía o referencia.';
    public static final String MSG_INVALID_MODE = 'Tipo de búsqueda no válido.';
    public static final String MSG_NOT_RESCHEDULABLE = 'Solo se puede reprogramar un envío Recolectado o En tránsito.';
    public static final String MSG_MAX_RESCHEDULES = 'Este envío ya se reprogramó el máximo de ' + MAX_RESCHEDULES + ' veces.';
    public static final String MSG_DATE_REQUIRED = 'Elige la nueva fecha de entrega.';
    public static final String MSG_DATE_OUT_OF_RANGE = 'La nueva fecha debe estar entre {0} y {1}.';
    public static final String MSG_NO_DATE_AVAILABLE = 'Ya no hay fechas disponibles para reprogramar este envío.';
    public static final String MSG_INSTRUCTIONS_TOO_LONG = 'Las instrucciones no pueden pasar de 2000 caracteres.';
    public static final String MSG_PROOF_NOT_AVAILABLE_YET = 'El comprobante está disponible cuando el envío está Entregado.';

    // ---------------------------------------------------------------- DTOs

    /** Una fila de resultado del rastreo: solo campos públicos (CA-001.2 / RN-01). */
    public class TrackingResult {
        @AuraEnabled public String key;
        @AuraEnabled public String query;
        @AuraEnabled public Boolean found;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String originCity;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public String lastUpdate; // dd/MM/yyyy HH:mm, Ciudad de México
        @AuraEnabled public String estimatedDelivery; // yyyy-MM-dd
    }

    /** Detalle de entrega: solo para quien conoce el código postal (CA-002.2 / RN-02). */
    public class DeliveryDetail {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public String estimatedDelivery; // yyyy-MM-dd
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public String deliveredAt; // dd/MM/yyyy HH:mm, Ciudad de México
        @AuraEnabled public Boolean proofAvailable;
        @AuraEnabled public Boolean canReschedule;
        @AuraEnabled public String rescheduleBlockedReason;
        @AuraEnabled public Integer reschedulesLeft;
        @AuraEnabled public String minRescheduleDate; // yyyy-MM-dd
        @AuraEnabled public String maxRescheduleDate; // yyyy-MM-dd
    }

    // ---------------------------------------------------------------- REQ-001

    /**
     * CA-001.1 a CA-001.5. Devuelve, en el orden de captura, los envíos encontrados por
     * cada valor o una fila "No encontrado".
     */
    @AuraEnabled
    public static List<TrackingResult> track(String mode, String rawValues) {
        if (mode != MODE_TRACKING && mode != MODE_REFERENCE) {
            throw error(MSG_INVALID_MODE);
        }
        List<String> values = parseValues(rawValues);
        if (values.isEmpty()) {
            throw error(MSG_NO_VALUES);
        }
        if (values.size() > MAX_VALUES) {
            throw error(MSG_TOO_MANY_VALUES);
        }

        // Las comparaciones de texto en SOQL no distinguen mayúsculas (CA-001.5).
        List<Shipment__c> shipments = mode == MODE_TRACKING
            ? [
                  SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                         Last_Location__c, Last_Update__c, Estimated_Delivery__c
                  FROM Shipment__c
                  WHERE Name IN :values
                  ORDER BY Name
                  LIMIT 200
              ]
            : [
                  SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                         Last_Location__c, Last_Update__c, Estimated_Delivery__c
                  FROM Shipment__c
                  WHERE Customer_Reference__c IN :values
                  ORDER BY Name
                  LIMIT 200
              ];

        Map<String, List<Shipment__c>> byKey = new Map<String, List<Shipment__c>>();
        for (Shipment__c s : shipments) {
            String k = normalizeKey(mode == MODE_TRACKING ? s.Name : s.Customer_Reference__c);
            if (!byKey.containsKey(k)) {
                byKey.put(k, new List<Shipment__c>());
            }
            byKey.get(k).add(s);
        }

        List<TrackingResult> results = new List<TrackingResult>();
        for (String value : values) {
            List<Shipment__c> matches = byKey.get(normalizeKey(value));
            if (matches == null || matches.isEmpty()) {
                TrackingResult r = new TrackingResult();
                r.key = 'nf-' + results.size();
                r.query = value;
                r.found = false;
                r.status = MSG_NOT_FOUND;
                results.add(r);
                continue;
            }
            for (Shipment__c s : matches) {
                results.add(toTrackingResult(s, value, results.size()));
            }
        }
        return results;
    }

    // ---------------------------------------------------------------- REQ-002

    /** CA-002.1 a CA-002.3. */
    @AuraEnabled
    public static DeliveryDetail getDeliveryDetail(String trackingNumber, String postalCode) {
        return toDeliveryDetail(verifyRecipient(trackingNumber, postalCode, false));
    }

    /** CA-002.4 y CA-002.5. El PDF viaja al navegador y no se guarda en Salesforce. */
    @AuraEnabled
    public static EntregaYaProofService.ProofFile getProof(String trackingNumber, String postalCode) {
        Shipment__c s = verifyRecipient(trackingNumber, postalCode, false);
        if (s.Status__c != STATUS_DELIVERED || String.isBlank(s.Proof_Id__c)) {
            throw error(MSG_PROOF_NOT_AVAILABLE_YET);
        }
        try {
            return EntregaYaProofService.fetchProof(s.Proof_Id__c, s.Name);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'EntregaYa proof failed for ' + s.Name + ': ' + e.getMessage());
            throw error(MSG_PROOF_UNAVAILABLE);
        }
    }

    // ---------------------------------------------------------------- REQ-003

    /**
     * CA-003.1 a CA-003.5. El historial de campos de Shipment__c registra quién y cuándo
     * cambió la fecha estimada, las instrucciones y el contador (CA-003.5).
     */
    @AuraEnabled
    public static DeliveryDetail reschedule(String trackingNumber, String postalCode, String newDate, String instructions) {
        Shipment__c s = verifyRecipient(trackingNumber, postalCode, true);

        String blocked = rescheduleBlockedReason(s);
        if (blocked != null) {
            throw error(blocked);
        }
        Date requested;
        try {
            requested = String.isBlank(newDate) ? null : Date.valueOf(newDate.trim());
        } catch (Exception e) {
            requested = null;
        }
        if (requested == null) {
            throw error(MSG_DATE_REQUIRED);
        }
        Date minDate = minRescheduleDate();
        Date maxDate = maxRescheduleDate(s);
        if (requested < minDate || requested > maxDate) {
            throw error(String.format(MSG_DATE_OUT_OF_RANGE, new List<String>{ formatDate(minDate), formatDate(maxDate) }));
        }
        String cleanInstructions = instructions == null ? null : instructions.trim();
        if (cleanInstructions != null && cleanInstructions.length() > 2000) {
            throw error(MSG_INSTRUCTIONS_TOO_LONG);
        }

        if (s.Original_Estimated_Delivery__c == null) {
            s.Original_Estimated_Delivery__c = s.Estimated_Delivery__c;
        }
        s.Estimated_Delivery__c = requested;
        s.Delivery_Instructions__c = String.isBlank(cleanInstructions) ? null : cleanInstructions;
        s.Reschedule_Count__c = currentRescheduleCount(s) + 1;
        update s;

        return toDeliveryDetail(s);
    }

    // ---------------------------------------------------------------- helpers

    @TestVisible
    static List<String> parseValues(String rawValues) {
        List<String> values = new List<String>();
        if (String.isBlank(rawValues)) {
            return values;
        }
        Set<String> seen = new Set<String>();
        for (String part : rawValues.split('[,\\r\\n]+')) {
            String v = part.trim();
            if (String.isBlank(v)) {
                continue;
            }
            String k = normalizeKey(v);
            if (seen.add(k)) {
                values.add(v);
            }
        }
        return values;
    }

    static String normalizeKey(String value) {
        return value == null ? '' : value.trim().toUpperCase();
    }

    @TestVisible
    static String normalizePostalCode(String value) {
        return value == null ? '' : value.replaceAll('\\s', '');
    }

    /** Verifica guía + código postal. Mismo mensaje si la guía no existe o si no coincide. */
    static Shipment__c verifyRecipient(String trackingNumber, String postalCode, Boolean forUpdate) {
        String tn = normalizeKey(trackingNumber);
        String cp = normalizePostalCode(postalCode);
        if (String.isBlank(tn) || String.isBlank(cp)) {
            throw error(MSG_DATA_MISMATCH);
        }
        List<Shipment__c> rows = forUpdate
            ? [
                  SELECT Id, Name, Status__c, Destination_Postal_Code__c, Recipient_Name__c, Recipient_Address__c,
                         Recipient_Phone__c, Estimated_Delivery__c, Original_Estimated_Delivery__c,
                         Delivery_Instructions__c, Delivered_At__c, Proof_Id__c, Reschedule_Count__c
                  FROM Shipment__c
                  WHERE Name = :tn
                  LIMIT 1
                  FOR UPDATE
              ]
            : [
                  SELECT Id, Name, Status__c, Destination_Postal_Code__c, Recipient_Name__c, Recipient_Address__c,
                         Recipient_Phone__c, Estimated_Delivery__c, Original_Estimated_Delivery__c,
                         Delivery_Instructions__c, Delivered_At__c, Proof_Id__c, Reschedule_Count__c
                  FROM Shipment__c
                  WHERE Name = :tn
                  LIMIT 1
              ];
        if (rows.isEmpty() || normalizePostalCode(rows[0].Destination_Postal_Code__c) != cp) {
            throw error(MSG_DATA_MISMATCH);
        }
        return rows[0];
    }

    static Integer currentRescheduleCount(Shipment__c s) {
        return s.Reschedule_Count__c == null ? 0 : s.Reschedule_Count__c.intValue();
    }

    @TestVisible
    static Date todayInMexicoCity() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', TIMEZONE));
    }

    static Date minRescheduleDate() {
        return todayInMexicoCity().addDays(1);
    }

    static Date maxRescheduleDate(Shipment__c s) {
        Date original = s.Original_Estimated_Delivery__c != null ? s.Original_Estimated_Delivery__c : s.Estimated_Delivery__c;
        return original == null ? null : original.addDays(MAX_DAYS_AFTER_ORIGINAL);
    }

    static String rescheduleBlockedReason(Shipment__c s) {
        if (!RESCHEDULABLE_STATUSES.contains(s.Status__c)) {
            return MSG_NOT_RESCHEDULABLE;
        }
        if (currentRescheduleCount(s) >= MAX_RESCHEDULES) {
            return MSG_MAX_RESCHEDULES;
        }
        Date maxDate = maxRescheduleDate(s);
        if (maxDate == null || maxDate < minRescheduleDate()) {
            return MSG_NO_DATE_AVAILABLE;
        }
        return null;
    }

    static TrackingResult toTrackingResult(Shipment__c s, String query, Integer index) {
        TrackingResult r = new TrackingResult();
        r.key = s.Name + '-' + index;
        r.query = query;
        r.found = true;
        r.trackingNumber = s.Name;
        r.status = s.Status__c;
        r.originCity = s.Origin_City__c;
        r.destinationCity = s.Destination_City__c;
        r.lastLocation = s.Last_Location__c;
        r.lastUpdate = formatDatetime(s.Last_Update__c);
        r.estimatedDelivery = isoDate(s.Estimated_Delivery__c);
        return r;
    }

    static DeliveryDetail toDeliveryDetail(Shipment__c s) {
        DeliveryDetail d = new DeliveryDetail();
        d.trackingNumber = s.Name;
        d.status = s.Status__c;
        d.recipientName = s.Recipient_Name__c;
        d.recipientAddress = s.Recipient_Address__c;
        d.recipientPhone = s.Recipient_Phone__c;
        d.estimatedDelivery = isoDate(s.Estimated_Delivery__c);
        d.deliveryInstructions = s.Delivery_Instructions__c;
        d.deliveredAt = formatDatetime(s.Delivered_At__c);
        d.proofAvailable = s.Status__c == STATUS_DELIVERED && String.isNotBlank(s.Proof_Id__c);
        d.rescheduleBlockedReason = rescheduleBlockedReason(s);
        d.canReschedule = d.rescheduleBlockedReason == null;
        d.reschedulesLeft = Math.max(0, MAX_RESCHEDULES - currentRescheduleCount(s));
        if (d.canReschedule) {
            d.minRescheduleDate = isoDate(minRescheduleDate());
            d.maxRescheduleDate = isoDate(maxRescheduleDate(s));
        }
        return d;
    }

    static String isoDate(Date d) {
        return d == null ? null : Datetime.newInstanceGmt(d, Time.newInstance(12, 0, 0, 0)).formatGmt('yyyy-MM-dd');
    }

    static String formatDate(Date d) {
        return d == null ? '' : Datetime.newInstanceGmt(d, Time.newInstance(12, 0, 0, 0)).formatGmt('dd/MM/yyyy');
    }

    @TestVisible
    static String formatDatetime(Datetime dt) {
        return dt == null ? null : dt.format('dd/MM/yyyy HH:mm', TIMEZONE);
    }

    static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
