/**
 * HU-03 — Consultar mis inscripciones.
 */
@IsTest
private class MyRegistrationsTest {
    @TestSetup
    static void setup() {
        Session__c a = DevSummitTestFactory.session('Apex Cursors en la práctica', 40, false);
        Session__c b = DevSummitTestFactory.session('Agentforce para devs', 25, true);
        b.Start__c = a.Start__c.addHours(-2);
        b.End__c = a.Start__c.addHours(-1);
        b.Room__c = 'Sala B';
        insert new List<Session__c>{ a, b };
        insert new List<Registration__c>{
            DevSummitTestFactory.registration(a.Id, 'ana@example.com'),
            DevSummitTestFactory.registration(b.Id, 'ana@example.com'),
            DevSummitTestFactory.registration(a.Id, 'otra@example.com')
        };
    }

    private static String codeOf(String email, String sessionName) {
        return [
            SELECT Confirmation_Code__c
            FROM Registration__c
            WHERE Attendee_Email__c = :email AND Session__r.Name = :sessionName
        ]
        .Confirmation_Code__c;
    }

    @IsTest
    static void ca03_1_anyCodeOfTheEmailWorks() {
        String code = codeOf('ana@example.com', 'Agentforce para devs');
        PublicSiteController.MyRegistrationsResult r = PublicSiteController.findMyRegistrations(' ANA@example.com ', code.toLowerCase());
        Assert.isTrue(r.found, 'Email y código sin distinguir mayúsculas');
        Assert.areEqual(2, r.registrations.size());
    }

    @IsTest
    static void ca03_2_showsAllRegistrationsOfThatEmail() {
        String code = codeOf('ana@example.com', 'Apex Cursors en la práctica');
        PublicSiteController.MyRegistrationsResult r = PublicSiteController.findMyRegistrations('ana@example.com', code);
        Assert.areEqual(2, r.registrations.size(), 'Solo las de ese email');
        PublicSiteController.MyRegistration first = r.registrations[0];
        Assert.areEqual('Agentforce para devs', first.sessionTitle, 'Ordenadas por horario');
        Assert.areEqual('Sala B', first.room);
        Assert.isNotNull(first.startTime);
        Assert.isNotNull(first.endTime);
        Assert.areEqual('Pendiente de aprobación', first.statusLabel);
        Assert.areEqual('Confirmada', r.registrations[1].statusLabel);
    }

    @IsTest
    static void ca03_3_mismatchShowsGenericMessage() {
        String otherCode = codeOf('otra@example.com', 'Apex Cursors en la práctica');
        for (PublicSiteController.MyRegistrationsResult r : new List<PublicSiteController.MyRegistrationsResult>{
            PublicSiteController.findMyRegistrations('ana@example.com', otherCode), // código de otra persona
            PublicSiteController.findMyRegistrations('nadie@example.com', 'ABCDEF'),
            PublicSiteController.findMyRegistrations('ana@example.com', ''),
            PublicSiteController.findMyRegistrations(null, null),
            PublicSiteController.findMyRegistrations('ana@example.com', 'ABC')
        }) {
            Assert.isFalse(r.found);
            Assert.areEqual('No encontramos inscripciones con esos datos.', r.message);
            Assert.isTrue(r.registrations.isEmpty());
        }
    }
}
