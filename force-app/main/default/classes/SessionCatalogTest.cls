/**
 * HU-01 — Buscar sesiones.
 */
@IsTest
private class SessionCatalogTest {
    @TestSetup
    static void setup() {
        Datetime base = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
        Session__c late = DevSummitTestFactory.session('Diseño de sharing a escala', 20, true);
        late.Track__c = 'Arquitectura';
        late.Start__c = base.addHours(4);
        late.End__c = base.addHours(5);
        late.Speaker_Name__c = 'Andrés Salgado';
        late.Sponsor_Name__c = 'Cumbre Consulting';

        Session__c early = DevSummitTestFactory.session('Apex Cursors en la práctica', 40, false);
        early.Start__c = base;
        early.End__c = base.addHours(1);
        early.Speaker_Name__c = 'Diego Ramírez';

        Session__c lwc = DevSummitTestFactory.session('LWC con estado, sin dolor', 1, false);
        lwc.Track__c = 'LWC';
        lwc.Start__c = base.addHours(2);
        lwc.End__c = base.addHours(3);
        lwc.Speaker_Name__c = 'Sofía Herrera';

        Session__c cancelled = DevSummitTestFactory.session('Sesión cancelada de Apex', 10, false);
        cancelled.Status__c = DevSummit.SESSION_CANCELLED;

        insert new List<Session__c>{ late, early, lwc, cancelled };
    }

    @IsTest
    static void ca01_1_showsOpenAndFullButNotCancelled() {
        Session__c lwc = [SELECT Id FROM Session__c WHERE Track__c = 'LWC'];
        insert DevSummitTestFactory.registration(lwc.Id, 'uno@example.com'); // la llena

        Test.startTest();
        List<PublicSiteController.SessionCard> cards = PublicSiteController.searchSessions(null, null);
        Test.stopTest();

        Assert.areEqual(3, cards.size(), 'Abiertas y llenas, sin canceladas');
        for (PublicSiteController.SessionCard c : cards) {
            Assert.isFalse(c.title.contains('cancelada'), 'Las canceladas no aparecen (RN-04)');
        }
    }

    @IsTest
    static void ca01_2_searchesTitleAndSpeakerCaseInsensitive() {
        Assert.areEqual(1, PublicSiteController.searchSessions('CURSORS', null).size(), 'Título sin distinguir mayúsculas');
        Assert.areEqual(1, PublicSiteController.searchSessions('sofía', null).size(), 'Nombre del speaker');
        Assert.areEqual(0, PublicSiteController.searchSessions('no existe', null).size());
        Assert.areEqual(0, PublicSiteController.searchSessions('%', null).size(), 'Los comodines se buscan literalmente');
    }

    @IsTest
    static void ca01_3_filtersByTrackOrAll() {
        Assert.areEqual(1, PublicSiteController.searchSessions(null, 'LWC').size());
        Assert.areEqual(3, PublicSiteController.searchSessions('', '').size(), 'Sin track muestra todos');
        Assert.areEqual(0, PublicSiteController.searchSessions(null, 'Track inventado').size(), 'Track inválido');
        Assert.areEqual(5, PublicSiteController.getTracks().size());
    }

    @IsTest
    static void ca01_4_cardShowsPublicFieldsOnly() {
        PublicSiteController.SessionCard c = PublicSiteController.searchSessions('sharing', null)[0];
        Assert.areEqual('Diseño de sharing a escala', c.title);
        Assert.areEqual('Arquitectura', c.track);
        Assert.isNotNull(c.startTime);
        Assert.isNotNull(c.endTime);
        Assert.areEqual('Sala A', c.room);
        Assert.areEqual('Andrés Salgado', c.speakerName);
        Assert.isTrue(c.isSponsored);
        Assert.areEqual('Cumbre Consulting', c.sponsorName);
        Assert.areEqual(20, c.availableSeats);

        String json = JSON.serialize(c);
        Assert.isFalse(json.contains('speakers.example'), 'No expone el email del speaker');
        Assert.isFalse(json.contains('0000 0001'), 'No expone el teléfono del speaker');
        Assert.isFalse(json.contains('45000'), 'No expone el monto del patrocinio');
        Assert.isFalse(json.contains('confidencial'), 'No expone notas internas');

        PublicSiteController.SessionCard notSponsored = PublicSiteController.searchSessions('cursors', null)[0];
        Assert.isNull(notSponsored.sponsorName, 'Sin patrocinador si no aplica');
    }

    @IsTest
    static void ca01_5_fullSessionIsMarkedFull() {
        Session__c lwc = [SELECT Id FROM Session__c WHERE Track__c = 'LWC'];
        insert DevSummitTestFactory.registration(lwc.Id, 'uno@example.com');

        PublicSiteController.SessionCard c = PublicSiteController.searchSessions(null, 'LWC')[0];
        Assert.isTrue(c.isFull);
        Assert.areEqual(0, c.availableSeats);
    }

    @IsTest
    static void ca01_6_orderedByStartTime() {
        List<PublicSiteController.SessionCard> cards = PublicSiteController.searchSessions(null, null);
        for (Integer i = 1; i < cards.size(); i++) {
            Assert.isTrue(cards[i - 1].startTime <= cards[i].startTime, 'Orden por hora de inicio');
        }
        Assert.areEqual('Apex Cursors en la práctica', cards[0].title);
    }
}
