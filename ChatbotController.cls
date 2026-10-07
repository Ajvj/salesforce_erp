/**
 * Thin proxy to the self-hosted chatbot service (Python + Ollama, no paid
 * AI API). Same pattern as the Java banking API proxy - Apex resolves
 * identity, signs a JWT, forwards the request, returns the reply text.
 */
public with sharing class ChatbotController {

    public class ChatbotException extends Exception {}

    private static final String NAMED_CREDENTIAL_ENDPOINT = 'callout:ChatbotAPI';
    private static final Integer TIMEOUT_MS = 120000;

    public class DocumentAnalysisResult {
        @AuraEnabled public String extractedText;
        @AuraEnabled public String pan;
        @AuraEnabled public String email;
        @AuraEnabled public List<String> amounts;
        @AuraEnabled public List<String> dates;
    }

    @AuraEnabled
    public static String sendMessage(String message) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();

            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT + '/chat');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + JwtTokenService.buildAccessToken(contactId));
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('ngrok-skip-browser-warning', 'true');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(JSON.serialize(new Map<String, Object>{ 'message' => message }));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (String) body.get('reply');
            }
            throw new ChatbotException('The assistant is unavailable right now (status ' + res.getStatusCode() + ').');
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled
    public static DocumentAnalysisResult analyzeDocument(String fileName, String contentBase64) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();

            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL_ENDPOINT + '/analyze-document-base64');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + JwtTokenService.buildAccessToken(contactId));
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('ngrok-skip-browser-warning', 'true');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(JSON.serialize(new Map<String, Object>{
                'fileName' => fileName,
                'contentBase64' => contentBase64
            }));

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                return parseDocumentAnalysis((Map<String, Object>) JSON.deserializeUntyped(res.getBody()));
            }
            throw new ChatbotException(
                'Document analysis is unavailable right now (status ' + res.getStatusCode() + ').'
            );
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @TestVisible
    private static DocumentAnalysisResult parseDocumentAnalysis(Map<String, Object> body) {
        DocumentAnalysisResult result = new DocumentAnalysisResult();
        result.extractedText = (String) body.get('extractedText');
        result.amounts = new List<String>();
        result.dates = new List<String>();
        Map<String, Object> fields = (Map<String, Object>) body.get('fields');
        if (fields == null) {
            return result;
        }
        result.pan = (String) fields.get('pan');
        result.email = (String) fields.get('email');
        if (fields.get('amounts_found') instanceof List<Object>) {
            for (Object item : (List<Object>) fields.get('amounts_found')) {
                result.amounts.add(String.valueOf(item));
            }
        }
        if (fields.get('dates_found') instanceof List<Object>) {
            for (Object item : (List<Object>) fields.get('dates_found')) {
                result.dates.add(String.valueOf(item));
            }
        }
        return result;
    }
}