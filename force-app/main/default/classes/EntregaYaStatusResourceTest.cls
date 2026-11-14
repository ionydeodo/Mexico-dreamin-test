@IsTest
private class EntregaYaStatusResourceTest {
    static User integrationUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = 'eya',
            Email = 'entregaya.integration@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'EntregaYa',
            LanguageLocaleKey = 'es_MX',
            LocaleSidKey = 'es_MX',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Mexico_City',
            Username = 'entregaya.' + unique + '@rutacargo.test'
        );
        // runAs aísla el DML de objetos de configuración (evita MIXED_DML_OPERATION).
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_EntregaYa_Integration'];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    static Map<String, Object> post(Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/entregaya/v1/status';
        req.httpMethod = 'POST';
        req.requestBody = body == null ? null : Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        EntregaYaStatusResource.receive();
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        out.put('_status', RestContext.response.statusCode);
        return out;
    }

    static Map<String, Object> body(String tracking, String status, String location, String ts, String proofId) {
        return new Map<String, Object>{
            'trackingNumber' => tracking,
            'status' => status,
            'location' => location,
            'timestamp' => ts,
            'proofId' => proofId
        };
    }

    @IsTest
    static void ca004_1_and_2_updatesStatusLocationAndTimestamp() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        Map<String, Object> out;
        System.runAs(integrationUser()) {
            out = post(body(s.Name, 'En reparto', 'Monterrey, NL', '2026-11-20T10:00:00-06:00', null));
        }
        Assert.areEqual(200, out.get('_status'));
        Assert.areEqual('updated', out.get('result'));
        Shipment__c after = RutaCargoTestData.reload(s.Id);
        Assert.areEqual('En reparto', after.Status__c);
        Assert.areEqual('Monterrey, NL', after.Last_Location__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0), after.Last_Update__c);
        Assert.isNull(after.Delivered_At__c);
    }

    @IsTest
    static void ca004_2_deliveredStoresDeliveryMomentAndProof() {
        Shipment__c s = RutaCargoTestData.insertShipment('En reparto', 'PED-1');
        Map<String, Object> out;
        System.runAs(integrationUser()) {
            out = post(body(s.Name.toLowerCase(), 'entregado', 'Monterrey, NL', '2026-11-20T13:15:00-06:00', 'PRF-88231'));
        }
        Assert.areEqual(200, out.get('_status'));
        Shipment__c after = RutaCargoTestData.reload(s.Id);
        Assert.areEqual('Entregado', after.Status__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 20, 19, 15, 0), after.Delivered_At__c);
        Assert.areEqual('PRF-88231', after.Proof_Id__c);
    }

    @IsTest
    static void ca004_3_unknownTrackingIsRejected() {
        Map<String, Object> out;
        System.runAs(integrationUser()) {
            out = post(body('RC999999999', 'En reparto', 'X', '2026-11-20T10:00:00-06:00', null));
        }
        Assert.areEqual(404, out.get('_status'));
        Assert.areEqual('TRACKING_NOT_FOUND', out.get('errorCode'));
        Assert.isTrue(((String) out.get('message')).contains('RC999999999'));
    }

    @IsTest
    static void ca004_3_invalidPayloadsAreRejectedWithClearErrors() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        Map<String, Integer> expectedStatus = new Map<String, Integer>();
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        System.runAs(integrationUser()) {
            results.add(post(body(s.Name, 'Perdido', 'X', '2026-11-20T10:00:00-06:00', null)));
            results.add(post(body('ABC123', 'En reparto', 'X', '2026-11-20T10:00:00-06:00', null)));
            results.add(post(body(s.Name, 'En reparto', 'X', 'ayer', null)));
            results.add(post(null));
        }
        List<String> codes = new List<String>{ 'INVALID_STATUS', 'INVALID_TRACKING_NUMBER', 'INVALID_TIMESTAMP', 'INVALID_REQUEST' };
        for (Integer i = 0; i < results.size(); i++) {
            Assert.areEqual(400, results[i].get('_status'));
            Assert.areEqual(codes[i], results[i].get('errorCode'));
            Assert.isNotNull(results[i].get('message'));
        }
        Assert.areEqual('En tránsito', RutaCargoTestData.reload(s.Id).Status__c);
    }

    @IsTest
    static void ca004_3_malformedJson() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf('{no es json');
        RestContext.request = req;
        RestContext.response = new RestResponse();
        System.runAs(integrationUser()) {
            EntregaYaStatusResource.receive();
        }
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void ca004_4_olderUpdatesAreIgnored() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        Map<String, Object> newer;
        Map<String, Object> older;
        System.runAs(integrationUser()) {
            newer = post(body(s.Name, 'En reparto', 'Monterrey, NL', '2026-11-20T10:00:00-06:00', null));
            older = post(body(s.Name, 'En tránsito', 'Saltillo, Coah.', '2026-11-20T08:00:00-06:00', null));
        }
        Assert.areEqual('updated', newer.get('result'));
        Assert.areEqual(200, older.get('_status'));
        Assert.areEqual('ignored', older.get('result'));
        Shipment__c after = RutaCargoTestData.reload(s.Id);
        Assert.areEqual('En reparto', after.Status__c);
        Assert.areEqual('Monterrey, NL', after.Last_Location__c);
    }

    @IsTest
    static void rn04_onlyEntregaYaCanSendUpdates() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User other = new User(
            Alias = 'otro',
            Email = 'otro@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Otro',
            LanguageLocaleKey = 'es_MX',
            LocaleSidKey = 'es_MX',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Mexico_City',
            Username = 'otro.' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@rutacargo.test'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert other;
        }
        Map<String, Object> out;
        System.runAs(other) {
            out = post(body(s.Name, 'En reparto', 'X', '2026-11-20T10:00:00-06:00', null));
        }
        Assert.areEqual(403, out.get('_status'));
        Assert.areEqual('En tránsito', RutaCargoTestData.reload(s.Id).Status__c);
    }

    @IsTest
    static void parsesIsoTimestamps() {
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0),
            EntregaYaStatusResource.parseTimestamp('2026-11-20T10:00:00-06:00')
        );
        Assert.isNull(EntregaYaStatusResource.parseTimestamp('20/11/2026'));
        Assert.isNull(EntregaYaStatusResource.parseTimestamp(null));
    }
}
