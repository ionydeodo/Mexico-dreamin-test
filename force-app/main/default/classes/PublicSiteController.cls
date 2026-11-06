/**
 * API del sitio público (Experience Cloud, usuario invitado sin login).
 *
 * Seguridad: el usuario invitado NO tiene permisos sobre los objetos. Esta clase corre sin sharing
 * a propósito y es la única puerta: valida cada entrada, escribe solo campos de una lista cerrada y
 * devuelve DTOs con los campos públicos. Nunca expone contacto del speaker, monto del patrocinio,
 * notas internas ni el código de confirmación (que solo llega por correo).
 */
public without sharing class PublicSiteController {
    private static final Integer MAX_RESULTS = 200;
    private static final Integer MAX_SEARCH_LENGTH = 80;
    private static final Integer MAX_TEXT_LENGTH = 120;
    private static final Integer MAX_EMAIL_LENGTH = 80;
    private static final Pattern EMAIL_PATTERN = Pattern.compile(
        '^[A-Za-z0-9.!#$%&\'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'
    );

    // ------------------------------------------------------------------ DTOs

    public class TrackOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        TrackOption(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }

    public class SessionCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String track;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String room;
        @AuraEnabled public String speakerName;
        @AuraEnabled public Boolean isSponsored;
        @AuraEnabled public String sponsorName;
        @AuraEnabled public Integer capacity;
        @AuraEnabled public Integer availableSeats;
        @AuraEnabled public Boolean isFull;
    }

    public class RegistrationResult {
        @AuraEnabled public Boolean success = false;
        /** OK, VALIDATION, ALREADY_REGISTERED, SESSION_FULL, SESSION_CANCELLED, NOT_FOUND, BUSY, ERROR */
        @AuraEnabled public String resultCode;
        @AuraEnabled public String message;
        /** Confirmed o Pending, solo cuando success = true. */
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public String attendeeEmail;
    }

    public class MyRegistration {
        @AuraEnabled public String sessionTitle;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String room;
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
    }

    public class MyRegistrationsResult {
        @AuraEnabled public Boolean found = false;
        @AuraEnabled public String message;
        @AuraEnabled public List<MyRegistration> registrations = new List<MyRegistration>();
    }

    // ------------------------------------------------------------------ HU-01 Buscar sesiones

    @AuraEnabled(cacheable=true)
    public static List<TrackOption> getTracks() {
        List<TrackOption> options = new List<TrackOption>();
        for (Schema.PicklistEntry e : Session__c.Track__c.getDescribe().getPicklistValues()) {
            if (e.isActive()) {
                options.add(new TrackOption(e.getValue(), e.getLabel()));
            }
        }
        return options;
    }

    /**
     * CA-01.1 sesiones Abiertas o Llenas (nunca Canceladas, RN-04) · CA-01.2 texto sobre título y speaker
     * sin distinguir mayúsculas · CA-01.3 filtro por track · CA-01.6 orden por hora de inicio.
     * No es cacheable: los cupos cambian a cada minuto durante la apertura.
     */
    @AuraEnabled
    public static List<SessionCard> searchSessions(String searchTerm, String track) {
        try {
            List<String> visible = new List<String>{ DevSummit.SESSION_OPEN, DevSummit.SESSION_FULL };
            String soql =
                'SELECT Id, Name, Track__c, Start__c, End__c, Room__c, Speaker_Name__c, Is_Sponsored__c, ' +
                'Sponsor_Name__c, Capacity__c, Available_Seats__c, Status__c ' +
                'FROM Session__c WHERE Status__c IN :visible';
            Map<String, Object> binds = new Map<String, Object>{ 'visible' => visible };

            String term = searchTerm == null ? '' : searchTerm.trim().left(MAX_SEARCH_LENGTH);
            if (String.isNotBlank(term)) {
                // Los comodines que escriba el usuario se buscan literalmente.
                String escaped = term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
                binds.put('term', '%' + escaped + '%');
                soql += ' AND (Name LIKE :term OR Speaker_Name__c LIKE :term)';
            }
            if (String.isNotBlank(track)) {
                if (!isValidTrack(track)) {
                    return new List<SessionCard>();
                }
                binds.put('track', track);
                soql += ' AND Track__c = :track';
            }
            soql += ' ORDER BY Start__c ASC, Name ASC LIMIT ' + MAX_RESULTS;

            List<SessionCard> cards = new List<SessionCard>();
            for (Session__c s : (List<Session__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
                cards.add(toCard(s));
            }
            return cards;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------ HU-02 Inscribirme

    /**
     * CA-02.1 validación · CA-02.2 duplicados · CA-02.3 / CA-02.8 cupo · CA-02.4 / CA-02.5 estado inicial.
     * El estado inicial, el código y el cupo los decide RegistrationTriggerHandler bajo bloqueo.
     */
    @AuraEnabled
    public static RegistrationResult register(String sessionId, String fullName, String email, String company, String jobTitle) {
        RegistrationResult result = new RegistrationResult();
        try {
            fullName = clean(fullName);
            email = DevSummit.normalizeEmail(email);
            company = clean(company);
            jobTitle = clean(jobTitle);

            if (String.isBlank(fullName) || String.isBlank(email) || String.isBlank(company)) {
                return fail(result, 'VALIDATION', System.Label.DS_Error_Required_Fields);
            }
            if (email.length() > MAX_EMAIL_LENGTH || !EMAIL_PATTERN.matcher(email).matches()) {
                return fail(result, 'VALIDATION', System.Label.DS_Error_Invalid_Email);
            }
            if (fullName.length() > MAX_TEXT_LENGTH || company.length() > MAX_TEXT_LENGTH ||
                (jobTitle != null && jobTitle.length() > MAX_TEXT_LENGTH)) {
                return fail(result, 'VALIDATION', System.Label.DS_Error_Too_Long);
            }
            Id sid = toSessionId(sessionId);
            if (sid == null) {
                return fail(result, 'NOT_FOUND', System.Label.DS_Error_Session_Not_Found);
            }

            Registration__c reg = new Registration__c(
                Session__c = sid,
                Attendee_Name__c = fullName,
                Attendee_Email__c = email,
                Company__c = company,
                Job_Title__c = jobTitle
            );
            Database.SaveResult sr = Database.insert(reg, false);
            if (!sr.isSuccess()) {
                return mapInsertError(result, sr.getErrors());
            }

            Registration__c saved = [SELECT Status__c FROM Registration__c WHERE Id = :reg.Id];
            result.success = true;
            result.resultCode = 'OK';
            result.status = saved.Status__c;
            result.statusLabel = DevSummit.statusLabel(Registration__c.Status__c, saved.Status__c);
            result.attendeeEmail = email;
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'DevSummit register: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return fail(result, 'ERROR', System.Label.DS_Error_Generic);
        }
    }

    // ------------------------------------------------------------------ HU-03 Mis inscripciones

    /**
     * CA-03.1 email + código de cualquiera de sus inscripciones · CA-03.2 todas las inscripciones del
     * email · CA-03.3 mensaje genérico si no coinciden (no revela si el email existe).
     */
    @AuraEnabled
    public static MyRegistrationsResult findMyRegistrations(String email, String confirmationCode) {
        MyRegistrationsResult result = new MyRegistrationsResult();
        try {
            email = DevSummit.normalizeEmail(email);
            String code = confirmationCode == null ? null : confirmationCode.trim().toUpperCase();
            if (String.isBlank(email) || String.isBlank(code) ||
                code.length() != ConfirmationCodeGenerator.CODE_LENGTH || email.length() > MAX_EMAIL_LENGTH) {
                result.message = System.Label.DS_Error_Registrations_Not_Found;
                return result;
            }
            Integer matches = [
                SELECT COUNT()
                FROM Registration__c
                WHERE Attendee_Email__c = :email AND Confirmation_Code__c = :code
            ];
            if (matches == 0) {
                result.message = System.Label.DS_Error_Registrations_Not_Found;
                return result;
            }
            for (Registration__c r : [
                SELECT Status__c, Session__r.Name, Session__r.Start__c, Session__r.End__c, Session__r.Room__c
                FROM Registration__c
                WHERE Attendee_Email__c = :email
                ORDER BY Session__r.Start__c ASC
                LIMIT 200
            ]) {
                MyRegistration m = new MyRegistration();
                m.sessionTitle = r.Session__r.Name;
                m.startTime = r.Session__r.Start__c;
                m.endTime = r.Session__r.End__c;
                m.room = r.Session__r.Room__c;
                m.status = r.Status__c;
                m.statusLabel = DevSummit.statusLabel(Registration__c.Status__c, r.Status__c);
                result.registrations.add(m);
            }
            result.found = true;
            return result;
        } catch (Exception e) {
            throw handled(e);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static SessionCard toCard(Session__c s) {
        SessionCard c = new SessionCard();
        c.id = s.Id;
        c.title = s.Name;
        c.track = s.Track__c;
        c.startTime = s.Start__c;
        c.endTime = s.End__c;
        c.room = s.Room__c;
        c.speakerName = s.Speaker_Name__c;
        c.isSponsored = s.Is_Sponsored__c;
        c.sponsorName = s.Is_Sponsored__c ? s.Sponsor_Name__c : null;
        c.capacity = s.Capacity__c == null ? 0 : s.Capacity__c.intValue();
        c.availableSeats = s.Available_Seats__c == null ? 0 : s.Available_Seats__c.intValue();
        c.isFull = s.Status__c == DevSummit.SESSION_FULL || c.availableSeats <= 0; // CA-01.5
        return c;
    }

    private static Boolean isValidTrack(String track) {
        for (TrackOption t : getTracks()) {
            if (t.value == track) {
                return true;
            }
        }
        return false;
    }

    private static Id toSessionId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id candidate = Id.valueOf(value.trim());
            return candidate.getSObjectType() == Session__c.SObjectType ? candidate : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static String clean(String value) {
        if (value == null) {
            return null;
        }
        String v = value.normalizeSpace();
        return String.isBlank(v) ? null : v;
    }

    private static RegistrationResult mapInsertError(RegistrationResult result, List<Database.Error> errors) {
        for (Database.Error err : errors) {
            String msg = err.getMessage();
            if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                // Carrera entre dos envíos del mismo email: el índice único Unique_Key__c lo detiene.
                return fail(result, 'ALREADY_REGISTERED', System.Label.DS_Error_Already_Registered);
            }
            if (msg == System.Label.DS_Error_Already_Registered) {
                return fail(result, 'ALREADY_REGISTERED', msg);
            }
            if (msg == System.Label.DS_Error_Session_Full) {
                return fail(result, 'SESSION_FULL', msg);
            }
            if (msg == System.Label.DS_Error_Session_Cancelled) {
                return fail(result, 'SESSION_CANCELLED', msg);
            }
            if (msg == System.Label.DS_Error_Session_Not_Found ||
                err.getStatusCode() == StatusCode.INVALID_CROSS_REFERENCE_KEY ||
                err.getStatusCode() == StatusCode.FIELD_INTEGRITY_EXCEPTION) {
                return fail(result, 'NOT_FOUND', System.Label.DS_Error_Session_Not_Found);
            }
            if (msg == System.Label.DS_Error_Busy || err.getStatusCode() == StatusCode.UNABLE_TO_LOCK_ROW) {
                return fail(result, 'BUSY', System.Label.DS_Error_Busy);
            }
        }
        System.debug(LoggingLevel.ERROR, 'DevSummit register DML: ' + errors);
        return fail(result, 'ERROR', System.Label.DS_Error_Generic);
    }

    private static RegistrationResult fail(RegistrationResult result, String code, String message) {
        result.success = false;
        result.resultCode = code;
        result.message = message;
        return result;
    }

    private static AuraHandledException handled(Exception e) {
        System.debug(LoggingLevel.ERROR, 'DevSummit: ' + e.getMessage() + '\n' + e.getStackTraceString());
        AuraHandledException ex = new AuraHandledException(System.Label.DS_Error_Generic);
        ex.setMessage(System.Label.DS_Error_Generic);
        return ex;
    }
}
