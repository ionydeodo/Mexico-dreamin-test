/**
 * Mantiene el estado Abierta/Llena coherente con la capacidad (RN-01, CA-06.2) y envía un solo
 * aviso a logística cada vez que una sesión pasa a Llena (CA-06.1, CA-06.3).
 */
public without sharing class SessionTriggerHandler {
    public static void beforeInsert(List<Session__c> sessions) {
        for (Session__c s : sessions) {
            if (s.Status__c != DevSummit.SESSION_CANCELLED) {
                // Una sesión nueva no tiene inscripciones.
                s.Status__c = SessionCapacityService.computeStatus(s.Capacity__c, 0);
            }
        }
    }

    public static void beforeUpdate(List<Session__c> sessions, Map<Id, Session__c> oldMap) {
        Set<Id> ids = new Set<Id>();
        for (Session__c s : sessions) {
            if (s.Status__c != DevSummit.SESSION_CANCELLED) {
                ids.add(s.Id);
            }
        }
        if (ids.isEmpty()) {
            return;
        }
        // Abierta/Llena no se edita a mano: siempre se deriva de la capacidad y las inscripciones.
        Map<Id, Integer> taken = SessionCapacityService.countSeatsTaken(ids);
        for (Session__c s : sessions) {
            if (ids.contains(s.Id)) {
                s.Status__c = SessionCapacityService.computeStatus(s.Capacity__c, taken.get(s.Id));
            }
        }
    }

    public static void afterUpdate(List<Session__c> sessions, Map<Id, Session__c> oldMap) {
        List<Session__c> becameFull = new List<Session__c>();
        for (Session__c s : sessions) {
            if (s.Status__c == DevSummit.SESSION_FULL && oldMap.get(s.Id).Status__c != DevSummit.SESSION_FULL) {
                becameFull.add(s);
            }
        }
        if (!becameFull.isEmpty()) {
            DevSummitEmailService.sendSessionFull(becameFull);
        }
    }
}
