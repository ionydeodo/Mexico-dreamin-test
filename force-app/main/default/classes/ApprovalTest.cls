/**
 * HU-04 — Aprobar inscripciones a sesiones patrocinadas.
 */
@IsTest
private class ApprovalTest {
    @TestSetup
    static void setup() {
        Session__c s = DevSummitTestFactory.insertSession('Agentforce para devs', 2, true);
        insert new List<Registration__c>{
            DevSummitTestFactory.registration(s.Id, 'ana@example.com'),
            DevSummitTestFactory.registration(s.Id, 'beto@example.com')
        };
    }

    @IsTest
    static void ca04_1_pendingListViewShowsRequiredColumns() {
        List<Registration__c> pending = [
            SELECT Session__r.Name, Attendee_Name__c, Company__c, Job_Title__c, CreatedDate
            FROM Registration__c
            WHERE Status__c = :DevSummit.REG_PENDING
        ];
        Assert.areEqual(2, pending.size());
        ListView lv = [SELECT Id FROM ListView WHERE SobjectType = 'Registration__c' AND DeveloperName = 'Pending_Approval'];
        Assert.isNotNull(lv, 'Vista de lista "Pendientes de aprobación"');
    }

    @IsTest
    static void ca04_2_approveConfirms() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Registration__c r = [SELECT Id FROM Registration__c WHERE Attendee_Email__c = 'ana@example.com'];
        System.runAs(DevSummitTestFactory.organizer()) {
            Test.startTest();
            update new Registration__c(Id = r.Id, Status__c = DevSummit.REG_CONFIRMED);
            Test.stopTest();
        }
        Registration__c after = [SELECT Status__c, Accreditation_Status__c FROM Registration__c WHERE Id = :r.Id];
        Assert.areEqual(DevSummit.REG_CONFIRMED, after.Status__c);
        Assert.areEqual(DevSummit.ACC_SENT, after.Accreditation_Status__c, 'CA-05.1: al aprobar se envía a AcrediPass');
    }

    @IsTest
    static void ca04_3_rejectRequiresReasonAndFreesSeat() {
        Registration__c r = [SELECT Id, Session__c FROM Registration__c WHERE Attendee_Email__c = 'ana@example.com'];
        Assert.areEqual(DevSummit.SESSION_FULL, [SELECT Status__c FROM Session__c].Status__c, 'Precondición: llena');

        System.runAs(DevSummitTestFactory.organizer()) {
            Database.SaveResult noReason = Database.update(new Registration__c(Id = r.Id, Status__c = DevSummit.REG_REJECTED), false);
            Assert.isFalse(noReason.isSuccess(), 'Rechazar exige motivo');
            Assert.areEqual('Indica el motivo del rechazo.', noReason.getErrors()[0].getMessage());

            update new Registration__c(Id = r.Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'Perfil no coincide');
        }
        Session__c s = [SELECT Status__c, Available_Seats__c FROM Session__c];
        Assert.areEqual(1, s.Available_Seats__c, 'Libera el cupo');
        Assert.areEqual(DevSummit.SESSION_OPEN, s.Status__c, 'CA-06.2: vuelve a Abierta');
        Assert.areEqual(DevSummit.REG_REJECTED, [SELECT Status__c FROM Registration__c WHERE Id = :r.Id].Status__c);
    }

    @IsTest
    static void ca04_4_attendeeReceivesDecisionEmail() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        List<Registration__c> regs = [SELECT Id, Attendee_Email__c FROM Registration__c ORDER BY Attendee_Email__c];
        System.runAs(DevSummitTestFactory.organizer()) {
            DevSummitEmailService.outbox.clear();
            update new List<Registration__c>{
                new Registration__c(Id = regs[0].Id, Status__c = DevSummit.REG_CONFIRMED),
                new Registration__c(Id = regs[1].Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'Cupo reservado para clientes')
            };
        }
        Map<String, Messaging.SingleEmailMessage> byTo = new Map<String, Messaging.SingleEmailMessage>();
        for (Messaging.SingleEmailMessage m : DevSummitEmailService.outbox) {
            byTo.put(m.getToAddresses()[0], m);
        }
        Assert.isTrue(byTo.get('ana@example.com').getSubject().contains('aprobada'));
        Assert.isTrue(byTo.get('beto@example.com').getSubject().contains('no fue aprobada'));
        Assert.isTrue(byTo.get('beto@example.com').getHtmlBody().contains('Cupo reservado para clientes'), 'Incluye el motivo');
    }

    @IsTest
    static void ca04_5_onlyOrganizersCanDecide() {
        Registration__c r = [SELECT Id FROM Registration__c WHERE Attendee_Email__c = 'ana@example.com'];
        System.runAs(DevSummitTestFactory.nonOrganizer()) {
            Database.SaveResult sr = Database.update(new Registration__c(Id = r.Id, Status__c = DevSummit.REG_CONFIRMED), false);
            Assert.isFalse(sr.isSuccess());
            Assert.areEqual('Solo los organizadores pueden aprobar o rechazar inscripciones.', sr.getErrors()[0].getMessage());
        }
    }

    @IsTest
    static void rn03_finalStatesCannotChange() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Registration__c r = [SELECT Id FROM Registration__c WHERE Attendee_Email__c = 'ana@example.com'];
        System.runAs(DevSummitTestFactory.organizer()) {
            update new Registration__c(Id = r.Id, Status__c = DevSummit.REG_CONFIRMED);
            Database.SaveResult back = Database.update(new Registration__c(Id = r.Id, Status__c = DevSummit.REG_PENDING), false);
            Assert.isFalse(back.isSuccess(), 'Confirmada es final');
            Database.SaveResult rej = Database.update(
                new Registration__c(Id = r.Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'x'),
                false
            );
            Assert.isFalse(rej.isSuccess(), 'Confirmada no pasa a Rechazada');
        }
    }
}
