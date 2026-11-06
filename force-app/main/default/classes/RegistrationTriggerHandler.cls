/**
 * Reglas de inscripción, sin importar el canal (sitio público, UI interna o API):
 *  - RN-01 / CA-02.3: nunca más inscripciones activas que la capacidad (bloqueo de la sesión).
 *  - RN-02 / CA-02.4 / CA-02.5: el estado inicial lo decide el sistema según el patrocinio.
 *  - RN-04: una sesión cancelada no acepta inscripciones.
 *  - CA-02.2: una inscripción activa por email y sesión (además del índice único Unique_Key__c).
 *  - RN-05 / CA-02.6: código de confirmación y correo al asistente.
 *  - HU-04 / HU-05 / HU-06: efectos de aprobar, rechazar y confirmar.
 */
public without sharing class RegistrationTriggerHandler {
    // ------------------------------------------------------------------ before insert
    public static void beforeInsert(List<Registration__c> registrations) {
        Set<Id> sessionIds = new Set<Id>();
        for (Registration__c r : registrations) {
            if (r.Session__c != null) {
                sessionIds.add(r.Session__c);
            }
        }

        Map<Id, Session__c> sessions;
        try {
            sessions = SessionCapacityService.lockSessions(sessionIds);
        } catch (SessionCapacityService.SessionBusyException e) {
            for (Registration__c r : registrations) {
                r.addError(System.Label.DS_Error_Busy);
            }
            return;
        }
        Map<Id, Integer> taken = SessionCapacityService.countSeatsTaken(sessions.keySet());

        Set<String> keys = new Set<String>();
        for (Registration__c r : registrations) {
            r.Attendee_Email__c = DevSummit.normalizeEmail(r.Attendee_Email__c);
            if (r.Session__c != null && r.Attendee_Email__c != null) {
                keys.add(DevSummit.uniqueKey(r.Session__c, r.Attendee_Email__c));
            }
        }
        Set<String> existingKeys = new Set<String>();
        for (Registration__c existing : [
            SELECT Unique_Key__c
            FROM Registration__c
            WHERE Unique_Key__c IN :keys
        ]) {
            existingKeys.add(existing.Unique_Key__c.toLowerCase());
        }

        List<Registration__c> accepted = new List<Registration__c>();
        for (Registration__c r : registrations) {
            Session__c s = sessions.get(r.Session__c);
            if (s == null) {
                r.addError(System.Label.DS_Error_Session_Not_Found);
                continue;
            }
            if (s.Status__c == DevSummit.SESSION_CANCELLED) {
                r.addError(System.Label.DS_Error_Session_Cancelled);
                continue;
            }
            String key = DevSummit.uniqueKey(s.Id, r.Attendee_Email__c).toLowerCase();
            if (existingKeys.contains(key)) {
                r.addError(System.Label.DS_Error_Already_Registered);
                continue;
            }
            Integer seatsTaken = taken.get(s.Id);
            if (seatsTaken >= s.Capacity__c) {
                r.addError(System.Label.DS_Error_Session_Full);
                continue;
            }
            taken.put(s.Id, seatsTaken + 1);
            existingKeys.add(key);

            r.Status__c = s.Is_Sponsored__c ? DevSummit.REG_PENDING : DevSummit.REG_CONFIRMED;
            r.Unique_Key__c = key;
            r.Rejection_Reason__c = null;
            r.Accreditation_Status__c = DevSummit.ACC_PENDING;
            r.Accreditation_Id__c = null;
            r.Accreditation_Error__c = null;
            accepted.add(r);
        }

        List<String> codes = ConfirmationCodeGenerator.generateUnique(accepted.size());
        for (Integer i = 0; i < accepted.size(); i++) {
            accepted[i].Confirmation_Code__c = codes[i];
        }
    }

    // ------------------------------------------------------------------ after insert
    public static void afterInsert(List<Registration__c> registrations) {
        Set<Id> confirmed = new Set<Id>();
        Set<Id> sessionIds = new Set<Id>();
        for (Registration__c r : registrations) {
            sessionIds.add(r.Session__c);
            if (r.Status__c == DevSummit.REG_CONFIRMED) {
                confirmed.add(r.Id);
            }
        }
        SessionCapacityService.refreshStatus(sessionIds);
        DevSummitEmailService.sendRegistrationReceived(new Map<Id, Registration__c>(registrations).keySet());
        AcrediPassService.enqueue(confirmed);
    }

    // ------------------------------------------------------------------ before update
    public static void beforeUpdate(List<Registration__c> registrations, Map<Id, Registration__c> oldMap) {
        for (Registration__c r : registrations) {
            Registration__c old = oldMap.get(r.Id);
            if (r.Confirmation_Code__c != old.Confirmation_Code__c) {
                r.Confirmation_Code__c.addError(System.Label.DS_Error_Code_Immutable);
            }
            r.Attendee_Email__c = DevSummit.normalizeEmail(r.Attendee_Email__c);
            if (r.Status__c == DevSummit.REG_REJECTED && old.Status__c != DevSummit.REG_REJECTED) {
                // Libera la llave: el asistente puede volver a inscribirse (las rechazadas no cuentan, CA-02.2).
                r.Unique_Key__c = null;
            } else if (r.Status__c != DevSummit.REG_REJECTED && r.Attendee_Email__c != old.Attendee_Email__c) {
                r.Unique_Key__c = DevSummit.uniqueKey(r.Session__c, r.Attendee_Email__c).toLowerCase();
            }
            // CA-05.4: una inscripción enviada con éxito no se vuelve a enviar.
            if (old.Accreditation_Status__c == DevSummit.ACC_SENT && r.Accreditation_Status__c != DevSummit.ACC_SENT) {
                r.Accreditation_Status__c.addError(System.Label.DS_Error_Already_Accredited);
            }
        }
    }

    // ------------------------------------------------------------------ after update
    public static void afterUpdate(List<Registration__c> registrations, Map<Id, Registration__c> oldMap) {
        Set<Id> toAccredit = new Set<Id>();
        Set<Id> decided = new Set<Id>();
        Set<Id> sessionsToRefresh = new Set<Id>();
        for (Registration__c r : registrations) {
            Registration__c old = oldMap.get(r.Id);
            Boolean statusChanged = r.Status__c != old.Status__c;
            if (statusChanged && old.Status__c == DevSummit.REG_PENDING) {
                decided.add(r.Id); // CA-04.4
            }
            if (statusChanged && r.Status__c == DevSummit.REG_CONFIRMED) {
                toAccredit.add(r.Id); // CA-05.1 (por aprobación)
            }
            if (statusChanged && r.Status__c == DevSummit.REG_REJECTED) {
                sessionsToRefresh.add(r.Session__c); // CA-04.3 / CA-06.2: libera cupo
            }
            // CA-05.3: el organizador reintenta regresando el estado de Error a Pendiente.
            Boolean retry =
                r.Status__c == DevSummit.REG_CONFIRMED &&
                old.Accreditation_Status__c == DevSummit.ACC_ERROR &&
                r.Accreditation_Status__c == DevSummit.ACC_PENDING;
            if (retry) {
                toAccredit.add(r.Id);
            }
        }
        SessionCapacityService.refreshStatus(sessionsToRefresh);
        DevSummitEmailService.sendDecision(decided);
        AcrediPassService.enqueue(toAccredit);
    }
}
