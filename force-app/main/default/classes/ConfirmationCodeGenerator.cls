/**
 * RN-05: códigos de 6 caracteres alfanuméricos en mayúsculas, sin caracteres ambiguos (0, O, 1, I).
 */
public inherited sharing class ConfirmationCodeGenerator {
    public static final String ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    public static final Integer CODE_LENGTH = 6;
    private static final Integer MAX_ATTEMPTS = 5;

    public static String generate() {
        String code = '';
        Integer size = ALPHABET.length();
        for (Integer i = 0; i < CODE_LENGTH; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), size);
            code += ALPHABET.substring(idx, idx + 1);
        }
        return code;
    }

    /**
     * Genera {@code count} códigos distintos entre sí y que no existen en la base de datos.
     * Confirmation_Code__c además es único a nivel base de datos como última barrera.
     */
    public static List<String> generateUnique(Integer count) {
        Set<String> codes = new Set<String>();
        for (Integer attempt = 0; attempt < MAX_ATTEMPTS && codes.size() < count; attempt++) {
            Set<String> candidates = new Set<String>();
            while (candidates.size() < count - codes.size()) {
                String c = generate();
                if (!codes.contains(c)) {
                    candidates.add(c);
                }
            }
            for (Registration__c taken : [
                SELECT Confirmation_Code__c
                FROM Registration__c
                WHERE Confirmation_Code__c IN :candidates
                WITH SYSTEM_MODE
            ]) {
                candidates.remove(taken.Confirmation_Code__c.toUpperCase());
            }
            codes.addAll(candidates);
        }
        return new List<String>(codes);
    }
}
