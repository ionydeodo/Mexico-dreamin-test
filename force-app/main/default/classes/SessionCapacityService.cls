/**
 * Regla de cupos (RN-01) y estado Abierta/Llena de las sesiones (CA-06.2).
 *
 * Concurrencia: toda inscripción bloquea la fila de su sesión con SELECT ... FOR UPDATE antes de
 * contar lugares ocupados. Las transacciones que compiten por la misma sesión se serializan, así que
 * la cuenta siempre incluye las inscripciones ya confirmadas por las transacciones anteriores.
 */
public without sharing class SessionCapacityService {
    /** Se lanza cuando no se pudo obtener el bloqueo de la sesión a tiempo (alta demanda). */
    public class SessionBusyException extends Exception {
    }

    /** Bloquea las sesiones para el resto de la transacción. */
    public static Map<Id, Session__c> lockSessions(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return new Map<Id, Session__c>();
        }
        try {
            return new Map<Id, Session__c>(
                [
                    SELECT Id, Name, Capacity__c, Status__c, Is_Sponsored__c, Room__c, Start__c, End__c
                    FROM Session__c
                    WHERE Id IN :sessionIds
                    FOR UPDATE
                ]
            );
        } catch (QueryException e) {
            // "Record Currently Unavailable": otra transacción retuvo el bloqueo más de 10 s.
            throw new SessionBusyException(System.Label.DS_Error_Busy, e);
        }
    }

    /** Lugares ocupados por sesión = inscripciones Confirmadas + Pendientes de aprobación (RN-01). */
    public static Map<Id, Integer> countSeatsTaken(Set<Id> sessionIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        for (Id sid : sessionIds) {
            result.put(sid, 0);
        }
        if (sessionIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Session__c sid, COUNT(Id) total
            FROM Registration__c
            WHERE Session__c IN :sessionIds AND Status__c IN :DevSummit.SEAT_TAKING_STATUSES
            GROUP BY Session__c
        ]) {
            result.put((Id) ar.get('sid'), (Integer) ar.get('total'));
        }
        return result;
    }

    /** Estado que corresponde a una sesión no cancelada según sus lugares ocupados. */
    public static String computeStatus(Decimal capacity, Integer seatsTaken) {
        Integer cap = capacity == null ? 0 : capacity.intValue();
        return seatsTaken >= cap ? DevSummit.SESSION_FULL : DevSummit.SESSION_OPEN;
    }

    /**
     * Recalcula Abierta/Llena después de que cambian las inscripciones. Solo actualiza las sesiones
     * cuyo estado cambia; el aviso de sesión llena lo envía SessionTriggerHandler.
     */
    public static void refreshStatus(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return;
        }
        Map<Id, Session__c> sessions = lockSessions(sessionIds);
        Map<Id, Integer> taken = countSeatsTaken(sessions.keySet());
        List<Session__c> toUpdate = new List<Session__c>();
        for (Session__c s : sessions.values()) {
            if (s.Status__c == DevSummit.SESSION_CANCELLED) {
                continue;
            }
            String expected = computeStatus(s.Capacity__c, taken.get(s.Id));
            if (expected != s.Status__c) {
                toUpdate.add(new Session__c(Id = s.Id, Status__c = expected));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
