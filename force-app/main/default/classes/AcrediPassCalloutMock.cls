/**
 * Mock configurable de la API de AcrediPass. Guarda las solicitudes recibidas para verificarlas.
 */
@IsTest
public class AcrediPassCalloutMock implements HttpCalloutMock {
    public Integer statusCode;
    public String body;
    public Boolean throwTimeout = false;
    public List<HttpRequest> requests = new List<HttpRequest>();

    public AcrediPassCalloutMock(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    public static AcrediPassCalloutMock success() {
        return new AcrediPassCalloutMock(201, '{"badgeId": "BDG-48213"}');
    }

    public HttpResponse respond(HttpRequest req) {
        requests.add(req);
        if (throwTimeout) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }
}
