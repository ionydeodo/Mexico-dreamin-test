/**
 * Constantes y configuración compartida del registro a sesiones de DevSummit CDMX.
 * Los valores de picklist son nombres de API; las etiquetas en español viven en la metadata.
 */
public inherited sharing class DevSummit {
    // Session__c.Status__c
    public static final String SESSION_OPEN = 'Open';
    public static final String SESSION_FULL = 'Full';
    public static final String SESSION_CANCELLED = 'Cancelled';

    // Registration__c.Status__c
    public static final String REG_PENDING = 'Pending';
    public static final String REG_CONFIRMED = 'Confirmed';
    public static final String REG_REJECTED = 'Rejected';

    // Registration__c.Accreditation_Status__c
    public static final String ACC_PENDING = 'Pending';
    public static final String ACC_SENT = 'Sent';
    public static final String ACC_ERROR = 'Error';

    /** RN-06: todos los horarios se muestran en hora de Ciudad de México. */
    public static final String TIME_ZONE = 'America/Mexico_City';

    /** Estados que ocupan cupo (RN-01). */
    public static final Set<String> SEAT_TAKING_STATUSES = new Set<String>{ REG_CONFIRMED, REG_PENDING };

    @TestVisible
    private static DevSummit_Setting__mdt settingsOverride;

    /** Configuración del evento (Custom Metadata DevSummit_Setting__mdt.Default). */
    public static DevSummit_Setting__mdt settings {
        get {
            if (settingsOverride != null) {
                return settingsOverride;
            }
            DevSummit_Setting__mdt s = DevSummit_Setting__mdt.getInstance('Default');
            if (s == null) {
                s = new DevSummit_Setting__mdt(
                    Sender_Name__c = 'DevSummit CDMX',
                    Sender_Address__c = 'no-reply@devsummit.example',
                    Logistics_Email__c = 'logistica@devsummit.example'
                );
            }
            return s;
        }
    }

    /** Llave que garantiza una sola inscripción activa por email y sesión (CA-02.2). */
    public static String uniqueKey(Id sessionId, String email) {
        return (String.valueOf(sessionId) + '|' + normalizeEmail(email)).toLowerCase();
    }

    public static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }

    /** Etiqueta en español de un valor de picklist. */
    public static String statusLabel(Schema.SObjectField field, String value) {
        for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
            if (e.getValue() == value) {
                return e.getLabel();
            }
        }
        return value;
    }

    /** Fecha y hora legible en hora de Ciudad de México (RN-06). */
    public static String formatDateTime(Datetime value) {
        return value == null ? '' : value.format('dd/MM/yyyy HH:mm', TIME_ZONE);
    }

    /** ISO 8601 con desplazamiento de Ciudad de México, p. ej. 2026-11-20T10:00:00-06:00. */
    public static String formatIsoMexicoCity(Datetime value) {
        return value == null ? null : value.format('yyyy-MM-dd\'T\'HH:mm:ssXXX', TIME_ZONE);
    }
}
