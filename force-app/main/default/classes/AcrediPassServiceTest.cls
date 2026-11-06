/**
 * HU-05 — Enviar inscripciones confirmadas a AcrediPass.
 */
@IsTest
private class AcrediPassServiceTest {
    @TestSetup
    static void setup() {
        // Los datos de @TestSetup quedan fuera de la transacción de cada prueba, así que la prueba
        // puede hacer callouts sin "uncommitted work pending".
        Session__c s = DevSummitTestFactory.insertSession('Diseño de sharing a escala', 20, false);
        insert DevSummitTestFactory.registration(s.Id, 'setup@example.com');
    }

    private static Registration__c confirmedRegistration() {
        return [
            SELECT Id, Attendee_Name__c, Attendee_Email__c, Company__c, Session__r.Name, Session__r.Start__c
            FROM Registration__c
            WHERE Attendee_Email__c = 'setup@example.com'
        ];
    }

    @IsTest
    static void ca05_1_confirmedRegistrationIsSentWithContract() {
        AcrediPassCalloutMock mock = AcrediPassCalloutMock.success();
        Test.setMock(HttpCalloutMock.class, mock);
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);

        Test.startTest();
        Registration__c r = DevSummitTestFactory.registration(s.Id, 'ana@example.com');
        insert r;
        Test.stopTest();

        Assert.areEqual(1, mock.requests.size());
        HttpRequest req = mock.requests[0];
        Assert.areEqual('POST', req.getMethod());
        Assert.areEqual('callout:AcrediPass/registrations', req.getEndpoint());
        Assert.areEqual('application/json', req.getHeader('Content-Type'));
        Assert.areEqual(10000, AcrediPassService.TIMEOUT_MS);

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
        Assert.areEqual(String.valueOf(r.Id), body.get('externalId'));
        Assert.areEqual('Ana López', body.get('fullName'));
        Assert.areEqual('ana@example.com', body.get('email'));
        Assert.areEqual('Nube Andina', body.get('company'));
        Assert.areEqual('Apex Cursors en la práctica', body.get('sessionTitle'));
        Assert.areEqual('2026-11-20T10:00:00-06:00', body.get('sessionStart'));
        Assert.isNull(req.getHeader('X-Api-Key'), 'La key la agrega la Named Credential, no el código');
    }

    @IsTest
    static void ca05_1_pendingRegistrationIsNotSent() {
        AcrediPassCalloutMock mock = AcrediPassCalloutMock.success();
        Test.setMock(HttpCalloutMock.class, mock);
        Session__c s = DevSummitTestFactory.insertSession('Agentforce para devs', 25, true);
        Test.startTest();
        insert DevSummitTestFactory.registration(s.Id, 'ana@example.com');
        Test.stopTest();
        Assert.areEqual(0, mock.requests.size(), 'Solo se envían las confirmadas');
    }

    @IsTest
    static void ca05_2_successStoresBadgeId() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Registration__c r = confirmedRegistration();
        Test.startTest();
        System.enqueueJob(new AcrediPassService(new List<Id>{ r.Id }));
        Test.stopTest();
        Registration__c after = [SELECT Accreditation_Status__c, Accreditation_Id__c, Accreditation_Error__c FROM Registration__c WHERE Id = :r.Id];
        Assert.areEqual(DevSummit.ACC_SENT, after.Accreditation_Status__c);
        Assert.areEqual('BDG-48213', after.Accreditation_Id__c);
        Assert.isNull(after.Accreditation_Error__c);
    }

    @IsTest
    static void ca05_3_failureIsMarkedAsError() {
        Test.setMock(HttpCalloutMock.class, new AcrediPassCalloutMock(503, 'Service Unavailable'));
        Registration__c r = confirmedRegistration();
        Test.startTest();
        System.enqueueJob(new AcrediPassService(new List<Id>{ r.Id }));
        Test.stopTest();
        Registration__c after = [SELECT Accreditation_Status__c, Accreditation_Error__c, Accreditation_Id__c FROM Registration__c WHERE Id = :r.Id];
        Assert.areEqual(DevSummit.ACC_ERROR, after.Accreditation_Status__c);
        Assert.isTrue(after.Accreditation_Error__c.contains('503'), after.Accreditation_Error__c);
        Assert.isNull(after.Accreditation_Id__c);
    }

    @IsTest
    static void ca05_3_organizerCanRetryFromRecord() {
        AcrediPassCalloutMock mock = new AcrediPassCalloutMock(201, '{"badgeId":"BDG-1"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Registration__c r = confirmedRegistration();
        update new Registration__c(Id = r.Id, Accreditation_Status__c = DevSummit.ACC_ERROR, Accreditation_Error__c = 'HTTP 503');

        // Acción "Reintentar envío a AcrediPass": Error -> Pendiente vuelve a enviar.
        System.runAs(DevSummitTestFactory.organizer()) {
            Test.startTest();
            update new Registration__c(Id = r.Id, Accreditation_Status__c = DevSummit.ACC_PENDING);
            Test.stopTest();
        }
        Registration__c after = [SELECT Accreditation_Status__c, Accreditation_Id__c, Accreditation_Error__c FROM Registration__c WHERE Id = :r.Id];
        Assert.areEqual(1, mock.requests.size());
        Assert.areEqual(DevSummit.ACC_SENT, after.Accreditation_Status__c);
        Assert.areEqual('BDG-1', after.Accreditation_Id__c);
        Assert.isNull(after.Accreditation_Error__c);
    }

    @IsTest
    static void ca05_3_timeoutAndBadResponsesAreErrors() {
        Registration__c full = confirmedRegistration();
        AcrediPassCalloutMock mock = AcrediPassCalloutMock.success();
        mock.throwTimeout = true;
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest(); // contexto nuevo: permite callouts después del DML de @TestSetup
        Registration__c timedOut = AcrediPassService.send(full);
        Assert.areEqual(DevSummit.ACC_ERROR, timedOut.Accreditation_Status__c, 'Timeout');
        Assert.isTrue(timedOut.Accreditation_Error__c.contains('Read timed out'), timedOut.Accreditation_Error__c);

        mock.throwTimeout = false;
        mock.statusCode = 401;
        mock.body = '{"error":"invalid key"}';
        Registration__c unauthorized = AcrediPassService.send(full);
        Assert.areEqual(DevSummit.ACC_ERROR, unauthorized.Accreditation_Status__c, '4xx');
        Assert.isTrue(unauthorized.Accreditation_Error__c.startsWith('HTTP 401'), unauthorized.Accreditation_Error__c);

        mock.statusCode = 201;
        mock.body = 'no es json';
        Assert.areEqual(DevSummit.ACC_ERROR, AcrediPassService.send(full).Accreditation_Status__c, 'Sin badgeId');
        Test.stopTest();
    }

    @IsTest
    static void ca05_4_alreadySentIsNeverResent() {
        AcrediPassCalloutMock mock = AcrediPassCalloutMock.success();
        Test.setMock(HttpCalloutMock.class, mock);
        Registration__c r = confirmedRegistration();
        update new Registration__c(Id = r.Id, Accreditation_Status__c = DevSummit.ACC_SENT, Accreditation_Id__c = 'BDG-9');

        Test.startTest();
        System.enqueueJob(new AcrediPassService(new List<Id>{ r.Id }));
        Test.stopTest();
        Assert.areEqual(0, mock.requests.size(), 'No se vuelve a enviar');

        Database.SaveResult sr = Database.update(new Registration__c(Id = r.Id, Accreditation_Status__c = DevSummit.ACC_PENDING), false);
        Assert.isFalse(sr.isSuccess(), 'No se puede regresar a Pendiente una inscripción enviada');
    }
}
