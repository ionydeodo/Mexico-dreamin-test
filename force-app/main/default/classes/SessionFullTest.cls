/**
 * HU-06 — Aviso de sesión llena.
 */
@IsTest
private class SessionFullTest {
    private static List<Messaging.SingleEmailMessage> logisticsMails() {
        List<Messaging.SingleEmailMessage> result = new List<Messaging.SingleEmailMessage>();
        for (Messaging.SingleEmailMessage m : DevSummitEmailService.outbox) {
            if (m.getToAddresses().contains('logistica@devsummit.example')) {
                result.add(m);
            }
        }
        return result;
    }

    @IsTest
    static void ca06_1_emailToLogisticsWhenSeatsReachZero() {
        DevSummitTestFactory.useDefaultSettings();
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Taller secreto: Claude Code en vivo', 2, false);
        insert DevSummitTestFactory.registration(s.Id, 'a@example.com');
        Assert.areEqual(0, logisticsMails().size(), 'Todavía hay cupo');

        insert DevSummitTestFactory.registration(s.Id, 'b@example.com');
        List<Messaging.SingleEmailMessage> mails = logisticsMails();
        Assert.areEqual(1, mails.size());
        String html = mails[0].getHtmlBody();
        Assert.isTrue(html.contains('Taller secreto: Claude Code en vivo'), 'Incluye la sesión');
        Assert.isTrue(html.contains('Sala A'), 'Incluye la sala');
        Assert.isTrue(html.contains('Capacidad: 2'), 'Incluye la capacidad');
    }

    @IsTest
    static void ca06_2_fullThenOpenAgainAfterRejection() {
        DevSummitTestFactory.useDefaultSettings();
        Session__c s = DevSummitTestFactory.insertSession('Diseño de sharing a escala', 1, true);
        Registration__c r = DevSummitTestFactory.registration(s.Id, 'a@example.com');
        insert r;
        Assert.areEqual(DevSummit.SESSION_FULL, [SELECT Status__c FROM Session__c].Status__c);

        System.runAs(DevSummitTestFactory.organizer()) {
            update new Registration__c(Id = r.Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'No aplica');
        }
        Assert.areEqual(DevSummit.SESSION_OPEN, [SELECT Status__c FROM Session__c].Status__c);
    }

    @IsTest
    static void ca06_3_oneEmailEachTimeSessionFills() {
        DevSummitTestFactory.useDefaultSettings();
        Session__c s = DevSummitTestFactory.insertSession('Agentforce para devs', 1, true);
        Registration__c r = DevSummitTestFactory.registration(s.Id, 'a@example.com');
        insert r;
        Assert.areEqual(1, logisticsMails().size(), 'Primera vez que se llena');

        // Ediciones de la sesión mientras sigue llena no reenvían el aviso.
        update new Session__c(Id = s.Id, Room__c = 'Sala C');
        Assert.areEqual(1, logisticsMails().size());

        System.runAs(DevSummitTestFactory.organizer()) {
            update new Registration__c(Id = r.Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'No aplica');
        }
        insert DevSummitTestFactory.registration(s.Id, 'b@example.com');
        Assert.areEqual(2, logisticsMails().size(), 'Se llenó de nuevo: un nuevo aviso');
    }

    @IsTest
    static void statusIsDerivedFromCapacity() {
        DevSummitTestFactory.useDefaultSettings();
        Session__c s = DevSummitTestFactory.insertSession('Data Cloud desde cero', 1, false);
        insert DevSummitTestFactory.registration(s.Id, 'a@example.com');
        Assert.areEqual(DevSummit.SESSION_FULL, [SELECT Status__c FROM Session__c].Status__c);

        update new Session__c(Id = s.Id, Capacity__c = 5);
        Assert.areEqual(DevSummit.SESSION_OPEN, [SELECT Status__c FROM Session__c].Status__c, 'Más capacidad reabre la sesión');

        update new Session__c(Id = s.Id, Status__c = DevSummit.SESSION_FULL);
        Assert.areEqual(DevSummit.SESSION_OPEN, [SELECT Status__c FROM Session__c].Status__c, 'Llena no se fija a mano');

        update new Session__c(Id = s.Id, Status__c = DevSummit.SESSION_CANCELLED);
        Assert.areEqual(DevSummit.SESSION_CANCELLED, [SELECT Status__c FROM Session__c].Status__c, 'Cancelar sí es manual');
    }
}
