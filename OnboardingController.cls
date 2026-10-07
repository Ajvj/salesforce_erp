public with sharing class OnboardingController {
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getApiInfo() {
        return new Map<String, Object>{
            'orgId' => UserInfo.getOrganizationId(),
            'username' => UserInfo.getUserName(),
            'instanceUrl' => URL.getOrgDomainUrl().toExternalForm(),
            'healthUrl' => URL.getOrgDomainUrl().toExternalForm() + '/services/apexrest/onboarding/v1/health',
            'ocrConfigured' => OcrService.isConfigured()
        };
    }

    @AuraEnabled(cacheable=true)
    public static List<Onboarding_Application__c> getApplications() {
        return [
            SELECT Id, Name, Channel__c, Status__c, Legal_Name__c, Email__c, AI_Risk_Score__c, CreatedDate
            FROM Onboarding_Application__c
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    @AuraEnabled
    public static Onboarding_Application__c createSample(String channel) {
        OnboardingApi.ApplicationInput input = new OnboardingApi.ApplicationInput();
        input.channel = String.isBlank(channel) ? 'Retail' : channel;
        input.legalName = input.channel == 'Corporate' ? 'Sample Corporate LLC' : 'Sample Retail Customer';
        input.email = 'sample@example.com';
        input.mobile = '+971500000000';
        input.nationality = 'AE';
        input.registrationNumber = input.channel == 'Corporate' ? 'CN-1001' : null;
        input.sourceSystem = 'Console';
        OnboardingApi.PartyInput party = new OnboardingApi.PartyInput();
        party.role = input.channel == 'Corporate' ? 'Director' : 'Primary';
        party.fullName = input.legalName;
        input.parties = new List<OnboardingApi.PartyInput>{ party };
        return OnboardingApi.createApplication(input);
    }
}