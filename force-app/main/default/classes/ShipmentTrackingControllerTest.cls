@IsTest
private class ShipmentTrackingControllerTest {
    // ------------------------------------------------------------ REQ-001

    @IsTest
    static void ca001_1_searchByTrackingNumberAndReference_upTo10Values() {
        Account a = RutaCargoTestData.sender();
        List<Shipment__c> rows = new List<Shipment__c>();
        for (Integer i = 0; i < 3; i++) {
            rows.add(RutaCargoTestData.shipment(a.Id, 'En tránsito', 'PED-' + i));
        }
        insert rows;
        List<Shipment__c> saved = [SELECT Name FROM Shipment__c ORDER BY Name];

        List<ShipmentTrackingController.TrackingResult> byGuide = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_TRACKING,
            saved[0].Name + ',' + saved[1].Name + '\n' + saved[2].Name
        );
        Assert.areEqual(3, byGuide.size());

        List<ShipmentTrackingController.TrackingResult> byRef = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_REFERENCE,
            'PED-1'
        );
        Assert.areEqual(1, byRef.size());
        Assert.isTrue(byRef[0].found);

        String eleven = 'A1,A2,A3,A4,A5,A6,A7,A8,A9,A10,A11';
        try {
            ShipmentTrackingController.track(ShipmentTrackingController.MODE_TRACKING, eleven);
            Assert.fail('Debió rechazar más de 10 valores');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_TOO_MANY_VALUES, e.getMessage());
        }
    }

    @IsTest
    static void ca001_1_rejectsEmptyAndInvalidMode() {
        try {
            ShipmentTrackingController.track(ShipmentTrackingController.MODE_TRACKING, ' , \n ');
            Assert.fail('Debió rechazar la búsqueda vacía');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_NO_VALUES, e.getMessage());
        }
        try {
            ShipmentTrackingController.track('email', 'x');
            Assert.fail('Debió rechazar el modo');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_INVALID_MODE, e.getMessage());
        }
    }

    @IsTest
    static void ca001_2_returnsOnlyPublicFields() {
        Shipment__c s = RutaCargoTestData.insertShipment('En reparto', 'PED-9');
        ShipmentTrackingController.TrackingResult r = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_TRACKING,
            s.Name
        )[0];
        Assert.areEqual(s.Name, r.trackingNumber);
        Assert.areEqual('En reparto', r.status);
        Assert.areEqual('Guadalajara, Jal.', r.originCity);
        Assert.areEqual('Monterrey, NL', r.destinationCity);
        Assert.areEqual('Centro de distribución Guadalajara', r.lastLocation);
        Assert.isNotNull(r.lastUpdate);
        Assert.isNotNull(r.estimatedDelivery);

        // RN-01 / RN-02 / RN-03: el JSON público no lleva datos personales ni internos.
        String json = JSON.serialize(r);
        for (String forbidden : new List<String>{ 'María', '64000', '5555', 'Ficticia', 'recepción', '250', 'frecuente', 'Remitente' }) {
            Assert.isFalse(json.contains(forbidden), 'El rastreo expone: ' + forbidden);
        }
    }

    @IsTest
    static void ca001_3_unknownValuesAreNotFound() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        List<ShipmentTrackingController.TrackingResult> results = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_TRACKING,
            s.Name + ',RC999999999'
        );
        Assert.areEqual(2, results.size());
        Assert.isTrue(results[0].found);
        Assert.isFalse(results[1].found);
        Assert.areEqual('RC999999999', results[1].query);
        Assert.areEqual(ShipmentTrackingController.MSG_NOT_FOUND, results[1].status);
    }

    @IsTest
    static void ca001_4_resultsCarrySortableStatusAndDate() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        ShipmentTrackingController.TrackingResult r = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_TRACKING,
            s.Name
        )[0];
        // El ordenamiento se hace en el componente; aquí se valida el formato ISO ordenable.
        Assert.isTrue(Pattern.matches('\\d{4}-\\d{2}-\\d{2}', r.estimatedDelivery));
        Assert.isNotNull(r.status);
    }

    @IsTest
    static void ca001_5_ignoresCaseAndSurroundingSpaces() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'Ped-Abc');
        List<ShipmentTrackingController.TrackingResult> byGuide = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_TRACKING,
            '   ' + s.Name.toLowerCase() + '   '
        );
        Assert.isTrue(byGuide[0].found);
        List<ShipmentTrackingController.TrackingResult> byRef = ShipmentTrackingController.track(
            ShipmentTrackingController.MODE_REFERENCE,
            '  pED-aBC '
        );
        Assert.isTrue(byRef[0].found);
        Assert.areEqual(s.Name, byRef[0].trackingNumber);
    }

    @IsTest
    static void rn05_trackingNumberIsRcPlusNineDigits() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        Assert.isTrue(Pattern.matches('RC\\d{9}', s.Name), s.Name);
    }

    // ------------------------------------------------------------ REQ-002

    @IsTest
    static void ca002_1_and_2_detailWithPostalCode() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.getDeliveryDetail(s.Name, ' 64 000 ');
        Assert.areEqual('María Prueba', d.recipientName);
        Assert.areEqual('Av. Ficticia 123, Col. Centro', d.recipientAddress);
        Assert.areEqual('+52 81 5555 0101', d.recipientPhone);
        Assert.isNotNull(d.estimatedDelivery);
        Assert.areEqual('Dejar en recepción', d.deliveryInstructions);

        String json = JSON.serialize(d);
        for (String forbidden : new List<String>{ '250', '150', 'frecuente', 'Remitente', 'example.com' }) {
            Assert.isFalse(json.contains(forbidden), 'El detalle expone: ' + forbidden);
        }
    }

    @IsTest
    static void ca002_3_wrongPostalCodeOrUnknownTracking() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        for (List<String> input : new List<List<String>>{
            new List<String>{ s.Name, '01000' },
            new List<String>{ 'RC999999999', '64000' },
            new List<String>{ s.Name, '' }
        }) {
            try {
                ShipmentTrackingController.getDeliveryDetail(input[0], input[1]);
                Assert.fail('Debió rechazar ' + input);
            } catch (AuraHandledException e) {
                Assert.areEqual(ShipmentTrackingController.MSG_DATA_MISMATCH, e.getMessage());
            }
        }
    }

    @IsTest
    static void ca002_4_downloadsProofFromEntregaYa() {
        Shipment__c s = delivered();
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, s.Name));
        Test.startTest();
        EntregaYaProofService.ProofFile f = ShipmentTrackingController.getProof(s.Name, '64000');
        Test.stopTest();
        Assert.areEqual('comprobante.pdf', f.fileName);
        Assert.areEqual('Ana López', f.signedBy);
        Assert.areEqual('JVBERi0xLjQK', f.pdfBase64);
        Assert.areEqual(0, [SELECT COUNT() FROM ContentVersion], 'El PDF no se guarda en Salesforce');
        Assert.areEqual(0, [SELECT COUNT() FROM Attachment], 'El PDF no se guarda en Salesforce');
    }

    @IsTest
    static void ca002_4_proofOnlyWhenDelivered() {
        Shipment__c s = RutaCargoTestData.insertShipment('En reparto', 'PED-1');
        try {
            ShipmentTrackingController.getProof(s.Name, '64000');
            Assert.fail('No debió pedir comprobante');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_PROOF_NOT_AVAILABLE_YET, e.getMessage());
        }
    }

    @IsTest
    static void ca002_4_proofRequiresPostalCode() {
        Shipment__c s = delivered();
        try {
            ShipmentTrackingController.getProof(s.Name, '11111');
            Assert.fail('Debió pedir el código postal correcto');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_DATA_MISMATCH, e.getMessage());
        }
    }

    @IsTest
    static void ca002_5_entregaYaErrorsShowFriendlyMessage() {
        Shipment__c s = delivered();
        Test.startTest();
        for (Integer status : new List<Integer>{ 401, 404, 503 }) {
            Test.setMock(HttpCalloutMock.class, new ProofMock(status, s.Name));
            try {
                ShipmentTrackingController.getProof(s.Name, '64000');
                Assert.fail('Debió fallar con HTTP ' + status);
            } catch (AuraHandledException e) {
                Assert.areEqual(ShipmentTrackingController.MSG_PROOF_UNAVAILABLE, e.getMessage());
            }
        }
    }

    @IsTest
    static void ca002_5_proofForAnotherShipmentIsRejected() {
        Shipment__c s = delivered();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, 'RC000000999'));
        try {
            ShipmentTrackingController.getProof(s.Name, '64000');
            Assert.fail('Debió rechazar un comprobante ajeno');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_PROOF_UNAVAILABLE, e.getMessage());
        }
    }

    @IsTest
    static void ca002_5_timeoutOrMalformedResponse() {
        Shipment__c s = delivered();
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ProofMock(-1, s.Name));
        try {
            ShipmentTrackingController.getProof(s.Name, '64000');
            Assert.fail('Debió fallar');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_PROOF_UNAVAILABLE, e.getMessage());
        }
    }

    // ------------------------------------------------------------ REQ-003

    @IsTest
    static void ca003_1_changesDateAndInstructions() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        Date target = s.Estimated_Delivery__c.addDays(2);
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.reschedule(
            s.Name,
            '64000',
            String.valueOf(target),
            '  Tocar el timbre dos veces  '
        );
        Shipment__c after = RutaCargoTestData.reload(s.Id);
        Assert.areEqual(target, after.Estimated_Delivery__c);
        Assert.areEqual('Tocar el timbre dos veces', after.Delivery_Instructions__c);
        Assert.areEqual(s.Estimated_Delivery__c, after.Original_Estimated_Delivery__c);
        Assert.areEqual(String.valueOf(target), d.estimatedDelivery);
    }

    @IsTest
    static void ca003_2_dateWindowFromTomorrowToOriginalPlus7() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        Date today = ShipmentTrackingController.todayInMexicoCity();
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.getDeliveryDetail(s.Name, '64000');
        Assert.areEqual(String.valueOf(today.addDays(1)), d.minRescheduleDate);
        Assert.areEqual(String.valueOf(s.Estimated_Delivery__c.addDays(7)), d.maxRescheduleDate);

        for (Date bad : new List<Date>{ today, s.Estimated_Delivery__c.addDays(8) }) {
            try {
                ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(bad), null);
                Assert.fail('Debió rechazar ' + bad);
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().startsWith('La nueva fecha debe estar entre'), e.getMessage());
            }
        }
        // Límite superior incluido
        ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(7)), null);
        // El límite se mide contra la fecha ORIGINAL, no contra la ya reprogramada.
        try {
            ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(8)), null);
            Assert.fail('Debió medir contra la fecha original');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().startsWith('La nueva fecha debe estar entre'), e.getMessage());
        }
    }

    @IsTest
    static void ca003_2_requiresValidDate() {
        Shipment__c s = RutaCargoTestData.insertShipment('En tránsito', 'PED-1');
        for (String bad : new List<String>{ null, '', 'mañana' }) {
            try {
                ShipmentTrackingController.reschedule(s.Name, '64000', bad, null);
                Assert.fail('Debió pedir fecha');
            } catch (AuraHandledException e) {
                Assert.areEqual(ShipmentTrackingController.MSG_DATE_REQUIRED, e.getMessage());
            }
        }
    }

    @IsTest
    static void ca003_3_onlyCollectedOrInTransit() {
        Account a = RutaCargoTestData.sender();
        List<Shipment__c> rows = new List<Shipment__c>();
        for (String status : new List<String>{ 'En reparto', 'Entregado', 'Incidencia' }) {
            rows.add(RutaCargoTestData.shipment(a.Id, status, status));
        }
        insert rows;
        for (Shipment__c s : [SELECT Name, Estimated_Delivery__c FROM Shipment__c]) {
            ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.getDeliveryDetail(s.Name, '64000');
            Assert.isFalse(d.canReschedule);
            try {
                ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(1)), null);
                Assert.fail('No debió reprogramar');
            } catch (AuraHandledException e) {
                Assert.areEqual(ShipmentTrackingController.MSG_NOT_RESCHEDULABLE, e.getMessage());
            }
        }
    }

    @IsTest
    static void ca003_4_maxTwoReschedules() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(1)), null);
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.reschedule(
            s.Name,
            '64000',
            String.valueOf(s.Estimated_Delivery__c.addDays(2)),
            null
        );
        Assert.isFalse(d.canReschedule);
        Assert.areEqual(0, d.reschedulesLeft);
        try {
            ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(3)), null);
            Assert.fail('No debió permitir una tercera reprogramación');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_MAX_RESCHEDULES, e.getMessage());
        }
        Assert.areEqual(2, RutaCargoTestData.reload(s.Id).Reschedule_Count__c);
    }

    @IsTest
    static void ca003_5_changesAreTrackedInFieldHistory() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.reschedule(
            s.Name,
            '64000',
            String.valueOf(s.Estimated_Delivery__c.addDays(1)),
            'Nuevo'
        );
        Assert.areEqual(String.valueOf(s.Estimated_Delivery__c.addDays(1)), d.estimatedDelivery);
        // El historial no se escribe dentro de las pruebas; se valida que esté activo.
        Assert.isTrue(Schema.getGlobalDescribe().containsKey('shipment__history'), 'Falta el historial de Shipment__c');
    }

    @IsTest
    static void ca003_reschedulingRequiresPostalCode() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        try {
            ShipmentTrackingController.reschedule(s.Name, '00000', String.valueOf(s.Estimated_Delivery__c.addDays(1)), null);
            Assert.fail('Debió exigir el código postal');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_DATA_MISMATCH, e.getMessage());
        }
    }

    @IsTest
    static void ca003_rejectsTooLongInstructions() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        try {
            ShipmentTrackingController.reschedule(s.Name, '64000', String.valueOf(s.Estimated_Delivery__c.addDays(1)), 'x'.repeat(2001));
            Assert.fail('Debió rechazar instrucciones largas');
        } catch (AuraHandledException e) {
            Assert.areEqual(ShipmentTrackingController.MSG_INSTRUCTIONS_TOO_LONG, e.getMessage());
        }
    }

    @IsTest
    static void ca003_noDatesLeftWhenWindowExpired() {
        Account a = RutaCargoTestData.sender();
        Shipment__c s = RutaCargoTestData.shipment(a.Id, 'En tránsito', 'PED-1');
        s.Estimated_Delivery__c = ShipmentTrackingController.todayInMexicoCity().addDays(-10);
        insert s;
        String name = [SELECT Name FROM Shipment__c WHERE Id = :s.Id].Name;
        ShipmentTrackingController.DeliveryDetail d = ShipmentTrackingController.getDeliveryDetail(name, '64000');
        Assert.isFalse(d.canReschedule);
        Assert.areEqual(ShipmentTrackingController.MSG_NO_DATE_AVAILABLE, d.rescheduleBlockedReason);
    }

    // ------------------------------------------------------------ RN-06 / RN-03

    @IsTest
    static void rn06_datesInMexicoCityTime() {
        // 18:30 UTC = 12:30 en Ciudad de México (UTC-6, sin horario de verano desde 2022)
        Assert.areEqual('10/11/2026 12:30', ShipmentTrackingController.formatDatetime(Datetime.newInstanceGmt(2026, 11, 10, 18, 30, 0)));
    }

    @IsTest
    static void marginFormula() {
        Shipment__c s = RutaCargoTestData.insertShipment('Recolectado', 'PED-1');
        Assert.areEqual(40, s.Margin__c.setScale(0));
    }

    // ------------------------------------------------------------ helpers

    static Shipment__c delivered() {
        Shipment__c s = RutaCargoTestData.insertShipment('Entregado', 'PED-D');
        s.Proof_Id__c = 'PRF-88231';
        s.Delivered_At__c = Datetime.now();
        update s;
        return s;
    }

    private class ProofMock implements HttpCalloutMock {
        Integer status;
        String tracking;

        ProofMock(Integer status, String tracking) {
            this.status = status;
            this.tracking = tracking;
        }

        public HttpResponse respond(HttpRequest req) {
            Assert.areEqual('GET', req.getMethod());
            Assert.areEqual('callout:EntregaYa/proofs/PRF-88231', req.getEndpoint());
            HttpResponse res = new HttpResponse();
            if (status == -1) {
                res.setStatusCode(200);
                res.setBody('<html>no es json</html>');
                return res;
            }
            res.setStatusCode(status);
            if (status == 200) {
                res.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'proofId' => 'PRF-88231',
                            'trackingNumber' => tracking,
                            'signedBy' => 'Ana López',
                            'fileName' => 'comprobante.pdf',
                            'pdfBase64' => 'JVBERi0xLjQK'
                        }
                    )
                );
            } else {
                res.setBody('{"error":"x"}');
            }
            return res;
        }
    }
}
