/**
 * RN-05 — Código de confirmación.
 */
@IsTest
private class ConfirmationCodeGeneratorTest {
    @IsTest
    static void rn05_formatWithoutAmbiguousCharacters() {
        for (Integer i = 0; i < 500; i++) {
            String code = ConfirmationCodeGenerator.generate();
            Assert.areEqual(6, code.length());
            Assert.areEqual(code.toUpperCase(), code);
            Assert.isTrue(code.isAlphanumeric());
            for (String banned : new List<String>{ '0', 'O', '1', 'I' }) {
                Assert.isFalse(code.contains(banned), 'Sin caracteres ambiguos: ' + code);
            }
        }
    }

    @IsTest
    static void generateUniqueReturnsDistinctCodes() {
        List<String> codes = ConfirmationCodeGenerator.generateUnique(200);
        Assert.areEqual(200, codes.size());
        Assert.areEqual(200, new Set<String>(codes).size());
        Assert.areEqual(0, ConfirmationCodeGenerator.generateUnique(0).size());
    }

    @IsTest
    static void timesAreFormattedInMexicoCity() {
        Datetime dt = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
        Assert.areEqual('20/11/2026 10:00', DevSummit.formatDateTime(dt));
        Assert.areEqual('2026-11-20T10:00:00-06:00', DevSummit.formatIsoMexicoCity(dt));
        Assert.areEqual('', DevSummit.formatDateTime(null));
        Assert.areEqual('Confirmada', DevSummit.statusLabel(Registration__c.Status__c, 'Confirmed'));
        Assert.areEqual('X', DevSummit.statusLabel(Registration__c.Status__c, 'X'));
    }
}
