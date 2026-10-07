/**
 * Calls Einstein Models API when Agentforce / Einstein GPT is enabled.
 * Returns null when the feature is off or the request fails so ERP AI can fall back.
 */
public with sharing class ERPEinsteinLlm {
    public static String generate(String prompt) {
        if (Test.isRunningTest() || String.isBlank(prompt)) {
            return null;
        }
        try {
            aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
            request.modelName = modelName();
            aiplatform.ModelsAPI_GenerationRequest body = new aiplatform.ModelsAPI_GenerationRequest();
            body.prompt = prompt.left(12000);
            request.body = body;
            aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
            aiplatform.ModelsAPI.createGenerations_Response response = api.createGenerations(request);
            if (response != null && response.Code200 != null && response.Code200.generation != null) {
                return blankToNull(response.Code200.generation.generatedText);
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    static String modelName() {
        List<AI_Integration__mdt> rows = [
            SELECT Model_Id__c
            FROM AI_Integration__mdt
            WHERE DeveloperName = 'ERP_Generative' AND Enabled__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!rows.isEmpty() && String.isNotBlank(rows[0].Model_Id__c)) {
            return rows[0].Model_Id__c;
        }
        return 'sfdc_ai__DefaultOpenAIGPT4OmniMini';
    }

    static String blankToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}