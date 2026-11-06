/**
 * HU-02 — Inscribirme a una sesión.
 */
@IsTest
private class RegistrationTest {
    private static PublicSiteController.RegistrationResult reg(Id sessionId, String email) {
        return PublicSiteController.register(sessionId, 'Ana López', email, 'Nube Andina', 'Developer');
    }

    @IsTest
    static void ca02_1_requiredFieldsAndEmailFormat() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);

        PublicSiteController.RegistrationResult r;
        r = PublicSiteController.register(s.Id, '  ', 'ana@example.com', 'Nube Andina', null);
        Assert.areEqual('VALIDATION', r.resultCode, 'Nombre obligatorio');
        r = PublicSiteController.register(s.Id, 'Ana', '', 'Nube Andina', null);
        Assert.areEqual('VALIDATION', r.resultCode, 'Email obligatorio');
        r = PublicSiteController.register(s.Id, 'Ana', 'ana@example.com', null, null);
        Assert.areEqual('VALIDATION', r.resultCode, 'Empresa obligatoria');
        Assert.areEqual(System.Label.DS_Error_Required_Fields, r.message);
        r = PublicSiteController.register(s.Id, 'Ana', 'ana@@example', 'Nube Andina', null);
        Assert.areEqual('VALIDATION', r.resultCode, 'Formato de email');
        Assert.areEqual(System.Label.DS_Error_Invalid_Email, r.message);
        r = PublicSiteController.register(s.Id, 'A'.repeat(121), 'ana@example.com', 'Nube Andina', null);
        Assert.areEqual('VALIDATION', r.resultCode, 'Longitud máxima');

        // El cargo es opcional.
        r = PublicSiteController.register(s.Id, 'Ana López', 'ANA@Example.com ', 'Nube Andina', null);
        Assert.isTrue(r.success, 'Resultado: ' + r.resultCode + ' ' + r.message);
        Registration__c saved = [SELECT Attendee_Email__c, Job_Title__c FROM Registration__c];
        Assert.areEqual('ana@example.com', saved.Attendee_Email__c, 'Email normalizado');
        Assert.isNull(saved.Job_Title__c);
    }

    @IsTest
    static void ca02_1_invalidSessionId() {
        Assert.areEqual('NOT_FOUND', reg(null, 'a@example.com').resultCode);
        Assert.areEqual('NOT_FOUND', PublicSiteController.register('no-es-un-id', 'Ana', 'a@example.com', 'X', null).resultCode);
        Assert.areEqual('NOT_FOUND', PublicSiteController.register(UserInfo.getUserId(), 'Ana', 'a@example.com', 'X', null).resultCode);
    }

    @IsTest
    static void ca02_2_oneActiveRegistrationPerEmailAndSession() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Agentforce para devs', 25, true);

        Assert.isTrue(reg(s.Id, 'ana@example.com').success);
        PublicSiteController.RegistrationResult dup = reg(s.Id, 'Ana@EXAMPLE.com');
        Assert.areEqual('ALREADY_REGISTERED', dup.resultCode);
        Assert.areEqual('Ya estás inscrito en esta sesión.', dup.message);

        // Las rechazadas no cuentan: se puede volver a inscribir.
        Registration__c first = [SELECT Id FROM Registration__c];
        System.runAs(DevSummitTestFactory.organizer()) {
            update new Registration__c(Id = first.Id, Status__c = DevSummit.REG_REJECTED, Rejection_Reason__c = 'Perfil no coincide');
        }
        Assert.isTrue(reg(s.Id, 'ana@example.com').success, 'Tras un rechazo puede inscribirse de nuevo');
    }

    @IsTest
    static void ca02_2_sameEmailInSameBatchIsRejected() {
        Session__c s = DevSummitTestFactory.insertSession('Data Cloud desde cero', 35, false);
        List<Database.SaveResult> results = Database.insert(
            new List<Registration__c>{
                DevSummitTestFactory.registration(s.Id, 'x@example.com'),
                DevSummitTestFactory.registration(s.Id, 'X@example.com')
            },
            false
        );
        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());
        Assert.areEqual(System.Label.DS_Error_Already_Registered, results[1].getErrors()[0].getMessage());
    }

    @IsTest
    static void ca02_3_neverExceedsCapacityCountingPending() {
        Session__c s = DevSummitTestFactory.insertSession('Diseño de sharing a escala', 2, true);
        List<Registration__c> batch = new List<Registration__c>();
        for (Integer i = 0; i < 5; i++) {
            batch.add(DevSummitTestFactory.registration(s.Id, 'p' + i + '@example.com'));
        }
        List<Database.SaveResult> results = Database.insert(batch, false);

        Integer ok = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                ok++;
            } else {
                Assert.areEqual(System.Label.DS_Error_Session_Full, sr.getErrors()[0].getMessage());
            }
        }
        Assert.areEqual(2, ok, 'Las pendientes de aprobación ocupan cupo');
        Session__c after = [SELECT Seats_Taken__c, Available_Seats__c, Status__c FROM Session__c WHERE Id = :s.Id];
        Assert.areEqual(2, after.Seats_Taken__c);
        Assert.areEqual(0, after.Available_Seats__c);
    }

    @IsTest
    static void ca02_4_nonSponsoredIsConfirmedImmediately() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);
        PublicSiteController.RegistrationResult r = reg(s.Id, 'ana@example.com');
        Assert.isTrue(r.success);
        Assert.areEqual(DevSummit.REG_CONFIRMED, r.status);
        Assert.areEqual('Confirmada', r.statusLabel);
    }

    @IsTest
    static void ca02_5_sponsoredIsPendingApproval() {
        Session__c s = DevSummitTestFactory.insertSession('Agentforce para devs', 25, true);
        PublicSiteController.RegistrationResult r = reg(s.Id, 'ana@example.com');
        Assert.areEqual(DevSummit.REG_PENDING, r.status);
        Assert.areEqual('Pendiente de aprobación', r.statusLabel);

        // RN-02: el estado inicial lo decide el sistema aunque el canal intente otro.
        Registration__c forced = DevSummitTestFactory.registration(s.Id, 'b@example.com');
        forced.Status__c = DevSummit.REG_CONFIRMED;
        insert forced;
        Assert.areEqual(DevSummit.REG_PENDING, [SELECT Status__c FROM Registration__c WHERE Id = :forced.Id].Status__c);
    }

    @IsTest
    static void ca02_6_codeAndEmailSentToAttendee() {
        DevSummitTestFactory.useDefaultSettings();
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);

        Test.startTest();
        PublicSiteController.RegistrationResult r = PublicSiteController.register(s.Id, 'Ana <b>López</b>', 'ana@example.com', 'Nube Andina', null);
        Test.stopTest();

        Registration__c saved = [SELECT Confirmation_Code__c FROM Registration__c];
        Assert.isTrue(Pattern.matches('[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}', saved.Confirmation_Code__c), 'RN-05');

        Messaging.SingleEmailMessage mail = findMail('ana@example.com');
        Assert.isNotNull(mail, 'Se envía correo al asistente');
        Assert.isTrue(mail.getHtmlBody().contains(saved.Confirmation_Code__c), 'Incluye el código');
        Assert.isTrue(mail.getHtmlBody().contains('Apex Cursors en la práctica'.escapeHtml4()), 'Incluye la sesión');
        Assert.isTrue(mail.getHtmlBody().contains('Sala A'), 'Incluye la sala');
        Assert.isTrue(mail.getHtmlBody().contains('20/11/2026 10:00'), 'Horario en hora de CDMX (RN-06)');
        Assert.isTrue(mail.getHtmlBody().contains('Confirmada'), 'Incluye el estado');
        Assert.isTrue(mail.getHtmlBody().contains('&lt;b&gt;'), 'Los datos del asistente se escapan');
        Assert.isFalse(mail.getHtmlBody().contains('{{'), 'No quedan marcadores sin combinar');
        Assert.areEqual('DevSummit CDMX', mail.getSenderDisplayName(), 'RN-07');
        Assert.areEqual('no-reply@devsummit.example', mail.getReplyTo(), 'RN-07');
    }

    @IsTest
    static void ca02_7_successDoesNotRevealCode() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);
        PublicSiteController.RegistrationResult r = reg(s.Id, 'ana@example.com');
        Registration__c saved = [SELECT Confirmation_Code__c FROM Registration__c];
        Assert.isTrue(r.success);
        Assert.areEqual('ana@example.com', r.attendeeEmail, 'La pantalla de éxito le pide revisar este correo');
        Assert.isFalse(JSON.serialize(r).contains(saved.Confirmation_Code__c), 'El código solo llega por correo');
    }

    @IsTest
    static void ca02_8_sessionFilledWhileFillingForm() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Taller secreto: Claude Code en vivo', 1, false);
        Assert.isTrue(reg(s.Id, 'primero@example.com').success);
        PublicSiteController.RegistrationResult late = reg(s.Id, 'segundo@example.com');
        Assert.areEqual('SESSION_FULL', late.resultCode);
        Assert.areEqual('Esta sesión ya no tiene cupos.', late.message);
    }

    @IsTest
    static void rn04_cancelledSessionRejectsRegistrations() {
        Session__c s = DevSummitTestFactory.session('Cancelada', 10, false);
        s.Status__c = DevSummit.SESSION_CANCELLED;
        insert s;
        PublicSiteController.RegistrationResult r = reg(s.Id, 'ana@example.com');
        Assert.areEqual('SESSION_CANCELLED', r.resultCode);
    }

    @IsTest
    static void rn05_codeIsImmutable() {
        Test.setMock(HttpCalloutMock.class, AcrediPassCalloutMock.success());
        Session__c s = DevSummitTestFactory.insertSession('Apex Cursors en la práctica', 40, false);
        Registration__c r = DevSummitTestFactory.registration(s.Id, 'ana@example.com');
        insert r;
        Database.SaveResult sr = Database.update(new Registration__c(Id = r.Id, Confirmation_Code__c = 'ZZZZZZ'), false);
        Assert.isFalse(sr.isSuccess());
    }

    @IsTest
    static void busyExceptionCarriesFriendlyMessage() {
        SessionCapacityService.SessionBusyException e = new SessionCapacityService.SessionBusyException(System.Label.DS_Error_Busy);
        Assert.areEqual('Hay mucha demanda en este momento. Intenta de nuevo en unos segundos.', e.getMessage());
    }

    private static Messaging.SingleEmailMessage findMail(String to) {
        for (Messaging.SingleEmailMessage m : DevSummitEmailService.outbox) {
            if (m.getToAddresses().contains(to)) {
                return m;
            }
        }
        return null;
    }
}
