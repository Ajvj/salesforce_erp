/**
 * Thin HTTP wrapper around the Java banking API. No business logic lives
 * here - it signs a request with the current customer's identity, sends it,
 * and hands back the parsed JSON body (or a friendly error) for the caller
 * to map into its own response shape.
 */
public with sharing class JavaBankingApiClient {

    public class ApiCalloutException extends Exception {}

    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:JavaBankingAPI';
    private static final Integer TIMEOUT_MS = 20000;

    public static Object get(String path, Id contactId) {
        return send('GET', path, contactId, null);
    }

    public static Object post(String path, Id contactId, String jsonBody) {
        return send('POST', path, contactId, jsonBody);
    }

    private static Object send(String method, String path, Id contactId, String jsonBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT + path);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + JwtTokenService.buildAccessToken(contactId));
        req.setHeader('Accept', 'application/json');
        req.setHeader('ngrok-skip-browser-warning', 'true'); // harmless outside local/ngrok dev
        req.setTimeout(TIMEOUT_MS);
        if (jsonBody != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(jsonBody);
        }

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            return JSON.deserializeUntyped(res.getBody());
        }
        throw new ApiCalloutException(extractErrorMessage(res));
    }

    public static String buildQueryString(Map<String, Object> params) {
        List<String> parts = new List<String>();
        for (String key : params.keySet()) {
            Object value = params.get(key);
            if (value == null) {
                continue;
            }
            parts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(formatValue(value), 'UTF-8'));
        }
        return parts.isEmpty() ? '' : '?' + String.join(parts, '&');
    }

    /**
     * String.valueOf(Date) produces "yyyy-MM-dd 00:00:00" (not plain ISO
     * "yyyy-MM-dd"), which Java's @DateTimeFormat(iso = DATE) binding
     * rejects with an unhandled 500. Date values need explicit yyyy-MM-dd
     * formatting; everything else uses the normal string conversion.
     */
    private static String formatValue(Object value) {
        if (value instanceof Date) {
            Date dateValue = (Date) value;
            return String.valueOf(dateValue.year())
                + '-' + String.valueOf(dateValue.month()).leftPad(2, '0')
                + '-' + String.valueOf(dateValue.day()).leftPad(2, '0');
        }
        return String.valueOf(value);
    }

    private static String extractErrorMessage(HttpResponse res) {
        try {
            Map<String, Object> errorBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            if (errorBody.containsKey('message')) {
                return (String) errorBody.get('message');
            }
        } catch (Exception parseError) {
            // fall through to the generic message below
        }
        return 'The banking service returned an unexpected error (status ' + res.getStatusCode() + ').';
    }
}