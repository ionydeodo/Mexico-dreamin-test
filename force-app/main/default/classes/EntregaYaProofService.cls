/**
 * Cliente del API de comprobantes de EntregaYa (CA-002.4, CA-002.5).
 * GET {URL base}/proofs/{proofId} con Authorization: Bearer {API key}.
 * La URL base y la API key viven en la Named Credential / External Credential "EntregaYa".
 */
public inherited sharing class EntregaYaProofService {
    public static final String NAMED_CREDENTIAL = 'callout:EntregaYa';
    public static final Integer TIMEOUT_MS = 10000; // recomendado por el proveedor

    public class EntregaYaException extends Exception {
    }

    public class ProofFile {
        @AuraEnabled public String fileName;
        @AuraEnabled public String signedBy;
        @AuraEnabled public String contentType;
        @AuraEnabled public String pdfBase64;
    }

    public static ProofFile fetchProof(String proofId, String expectedTrackingNumber) {
        if (String.isBlank(proofId)) {
            throw new EntregaYaException('Falta el identificador del comprobante');
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(NAMED_CREDENTIAL + '/proofs/' + EncodingUtil.urlEncode(proofId, 'UTF-8'));
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new EntregaYaException('EntregaYa respondió HTTP ' + res.getStatusCode());
        }

        Map<String, Object> body;
        try {
            body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            throw new EntregaYaException('Respuesta de EntregaYa no es JSON válido');
        }
        String pdf = (String) body.get('pdfBase64');
        String tracking = (String) body.get('trackingNumber');
        if (String.isBlank(pdf)) {
            throw new EntregaYaException('La respuesta no trae el PDF');
        }
        // Defensa: el comprobante debe pertenecer al envío que se está consultando (RN-02).
        if (String.isNotBlank(expectedTrackingNumber) && !expectedTrackingNumber.equalsIgnoreCase(tracking)) {
            throw new EntregaYaException('El comprobante no corresponde al envío');
        }

        ProofFile f = new ProofFile();
        String name = (String) body.get('fileName');
        f.fileName = String.isBlank(name) ? 'comprobante-' + expectedTrackingNumber + '.pdf' : name;
        f.signedBy = (String) body.get('signedBy');
        f.contentType = 'application/pdf';
        f.pdfBase64 = pdf;
        return f;
    }
}
