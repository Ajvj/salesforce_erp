public without sharing class EngageIQRestUtil {
    public static void cors() {
        if (RestContext.response == null) {
            return;
        }
        RestContext.response.addHeader('Access-Control-Allow-Origin', '*');
        RestContext.response.addHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        RestContext.response.addHeader('Access-Control-Allow-Headers', 'Content-Type');
        RestContext.response.addHeader('Content-Type', 'application/json');
    }

    public static String body() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            return '';
        }
        return RestContext.request.requestBody.toString();
    }

    public static String path(RestRequest req, String marker) {
        String uri = req == null || req.requestURI == null ? '' : req.requestURI;
        if (uri.contains(marker)) {
            return uri.substringAfter(marker).removeStart('/').removeEnd('/');
        }
        return uri.removeStart('/').removeEnd('/');
    }

    public static void write(Integer statusCode, Object payload) {
        cors();
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}