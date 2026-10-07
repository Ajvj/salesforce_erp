@IsTest
private class OnboardingApiTest {
    private class OcrMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"probabilities":[{"label":"JANE DOE"},{"label":"P1234567"}]}');
            return res;
        }
    }

    @IsTest
    static void createsRetailApplicationAndSummarizes() {
        OnboardingApi.ApplicationInput input = new OnboardingApi.ApplicationInput();
        input.channel = 'Retail';
        input.legalName = 'Jane Doe';
        input.email = 'jane@example.com';
        OnboardingApi.PartyInput party = new OnboardingApi.PartyInput();
        party.fullName = 'Jane Doe';
        party.role = 'Primary';
        input.parties = new List<OnboardingApi.PartyInput>{ party };

        Test.startTest();
        Onboarding_Application__c app = OnboardingApi.createApplication(input);
        Onboarding_Application__c summarized = OnboardingAiService.persist(app.Id);
        Test.stopTest();

        System.assertEquals('Jane Doe', app.Legal_Name__c);
        System.assertEquals(1, app.Parties__r.size());
        System.assert(summarized.AI_Risk_Score__c != null);
        System.assertEquals('AI Review', summarized.Status__c);
    }

    @IsTest
    static void restHealthAndGetApplication() {
        OnboardingApi.ApplicationInput input = new OnboardingApi.ApplicationInput();
        input.legalName = 'Corp One';
        input.channel = 'Corporate';
        input.registrationNumber = 'CN-9';
        Onboarding_Application__c app = OnboardingApi.createApplication(input);

        RestRequest healthReq = new RestRequest();
        healthReq.requestURI = '/services/apexrest/onboarding/v1/health';
        healthReq.httpMethod = 'GET';
        RestContext.request = healthReq;
        RestContext.response = new RestResponse();
        OnboardingApi.doGet();
        Map<String, Object> health = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('ok', health.get('status'));

        RestRequest getReq = new RestRequest();
        getReq.requestURI = '/services/apexrest/onboarding/v1/applications/' + app.Id;
        getReq.httpMethod = 'GET';
        RestContext.request = getReq;
        RestContext.response = new RestResponse();
        OnboardingApi.doGet();
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void restCreateAndDocumentWithoutOcrToken() {
        RestRequest createReq = new RestRequest();
        createReq.requestURI = '/services/apexrest/onboarding/v1/applications';
        createReq.httpMethod = 'POST';
        createReq.requestBody = Blob.valueOf('{"legalName":"API Person","channel":"Retail","parties":[{"fullName":"API Person","role":"Primary"}]}');
        RestContext.request = createReq;
        RestContext.response = new RestResponse();
        OnboardingApi.doPost();
        System.assertEquals(201, RestContext.response.statusCode);
        Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Id appId = (Id) created.get('Id');

        RestRequest docReq = new RestRequest();
        docReq.requestURI = '/services/apexrest/onboarding/v1/applications/' + appId + '/documents';
        docReq.httpMethod = 'POST';
        docReq.requestBody = Blob.valueOf(
            '{"documentType":"Passport","fileName":"passport.png","base64Data":"' +
            EncodingUtil.base64Encode(Blob.valueOf('fake-image')) +
            '"}'
        );
        RestContext.request = docReq;
        RestContext.response = new RestResponse();
        OnboardingApi.doPost();
        System.assertEquals(201, RestContext.response.statusCode);

        RestRequest aiReq = new RestRequest();
        aiReq.requestURI = '/services/apexrest/onboarding/v1/applications/' + appId + '/ai/summarize';
        aiReq.httpMethod = 'POST';
        aiReq.requestBody = Blob.valueOf('{}');
        RestContext.request = aiReq;
        RestContext.response = new RestResponse();
        OnboardingApi.doPost();
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void ocrParsesAndCalloutSucceeds() {
        OcrService.testConfig = new AI_Integration__mdt(
            Enabled__c = true,
            Endpoint__c = 'https://api.einstein.ai/v2/vision/ocr',
            Bearer_Token__c = 'token',
            Model_Id__c = 'OCRModel'
        );
        Test.setMock(HttpCalloutMock.class, new OcrMock());
        Test.startTest();
        OcrService.Result res = OcrService.extract(Blob.valueOf('img'), 'id.png');
        String parsed = OcrService.parseText('{"probabilities":[{"label":"HELLO"}]}');
        Test.stopTest();
        System.assertEquals('Complete', res.status);
        System.assertEquals('HELLO', parsed);
        System.assertEquals(true, OcrService.isConfigured());
        String ocrSpace = OcrService.parseText('{"ParsedResults":[{"ParsedText":"INDIAN PASSPORT JOHN DOE"}]}');
        System.assert(ocrSpace.contains('INDIAN PASSPORT'));
    }

    @IsTest
    static void ocrMapsIndianPassportNameAndAddress() {
        OcrService.Result parsed = new OcrService.Result();
        parsed.extractedText =
            'REPUBLIC OF INDIA\nPASSPORT\nSurname\nLAKSHMI\nGiven Name(s)\nSEETHA\nNationality INDIAN\n' +
            'Sex F\nDate of Birth 15/08/1990\nPlace of Birth CHENNAI\nAddress\n12 ANNA NAGAR\nCHENNAI\nTAMIL NADU 600040\n' +
            'P<INDLAKSHMI<<SEETHA<<<<<<<<<<<<<<<<<<<';
        OcrService.applyHeuristics(parsed);
        System.assertEquals('Seetha', parsed.extractedFirstName);
        System.assertEquals('Lakshmi', parsed.extractedLastName);
        System.assertEquals(Date.newInstance(1990, 8, 15), parsed.extractedDob);
        System.assertEquals('Female', parsed.extractedGender);
        System.assertEquals('Chennai', parsed.extractedPlaceOfBirth);
        System.assert(parsed.extractedStreet.contains('Anna'));
        System.assertEquals('600040', parsed.extractedPostal);
        System.assertEquals('Tamil Nadu', parsed.extractedState);
        OcrService.Result us = new OcrService.Result();
        us.extractedText = 'UNITED STATES OF AMERICA\nSurname/Nom\nDOE\nGiven Names/Prenoms\nJOHN ADAM\nDate of Birth 14 JAN 1985\nDate of Expiry 01 JAN 2030';
        OcrService.applyHeuristics(us);
        System.assertEquals('John Adam', us.extractedFirstName);
        System.assertEquals('Doe', us.extractedLastName);
        System.assertEquals(Date.newInstance(1985, 1, 14), us.extractedDob);
        System.assertEquals(Date.newInstance(2030, 1, 1), us.extractedExpiry);
        OcrService.Result iso = new OcrService.Result();
        iso.extractedText = 'Date of Birth 1990-08-15\nSex Male\nPassport No Z1234567';
        OcrService.applyHeuristics(iso);
        System.assertEquals(Date.newInstance(1990, 8, 15), iso.extractedDob);
        System.assertEquals('Male', iso.extractedGender);
        System.assertEquals('Z1234567', iso.extractedId);

        OcrService.Result scan = new OcrService.Result();
        scan.extractedText =
            'TUIT/ REPUBLIC OF INDIA\nстеч / Туре\n#TE / Code.\nIND\nHRAE /INDIAN\n34-P5 / Surname\nDHAYALAN\n' +
            'PeTT +741 -74/ Given Name(s)\nHARINI\noprfafla / Date of Birth\n01/07/2003\n' +
            'GH FuT/ Place of Birth\nHOSUR, TAMIL NADU\nORT aSeA SEI PeTP/ Place ofissue\nCHENNAI\n' +
            'arêt ari d fefa/ Date of issue\n27/04/2026\napena dt ffr / Date of Expity\n26/04/2036\n' +
            'PaRT / Sex\nF\nAS358873\nPKINDDHAYALAN<<HARINI<<<<<<<<<<<<<<<<<<<<<<<\n' +
            'AS358873<2IND0307019F36042693066696453426<28\n' +
            'apas ar -179/ Name of Father / Legal Guardian\nAS35887\nDHAYALAN\n' +
            '4T8I 87 45/ Name of Mother\nKALAIVANI\nviê ar gel aT 4/ Name of Spouse\n' +
            'D NO 6,PHASE 2, NEAR ADHIYAMAN COLLEGE\nVALLALAR NAGAR,HOSUR, KRISHNAGIRI\n' +
            'PIN:635109, TAMIL NADU, INDIA\nINCOME TAX DEPARTMENT\nGOVT. OF INDIA\n' +
            'Permanent Account Number Card\nBJRPH7386F\n7ТH / Name\nHARINI\n' +
            'A 2 / Father\'s Name\nDHAYALAN\nDate of Birth\n01/07/2003';
        OcrService.applyHeuristics(scan);
        System.assertEquals('Harini', scan.extractedFirstName);
        System.assertEquals('Dhayalan', scan.extractedLastName);
        System.assertEquals(Date.newInstance(2003, 7, 1), scan.extractedDob);
        System.assertEquals(Date.newInstance(2036, 4, 26), scan.extractedExpiry);
        System.assertEquals('Female', scan.extractedGender);
        System.assertEquals('BJRPH7386F', scan.extractedPan);
        System.assertEquals('AS358873', scan.extractedId);
        System.assertEquals('635109', scan.extractedPostal);
        System.assertEquals('Tamil Nadu', scan.extractedState);
        System.assertEquals('Hosur', scan.extractedCity);
        System.assert(scan.extractedStreet.contains('Adhiyaman') || scan.extractedStreet.contains('Phase'));
        System.assertEquals('Dhayalan', scan.extractedFatherName);
        System.assertEquals('Kalaivani', scan.extractedMotherName);
    }

    @IsTest
    static void controllerSampleAndLists() {
        Test.startTest();
        Onboarding_Application__c retail = OnboardingController.createSample('Retail');
        Onboarding_Application__c corp = OnboardingController.createSample('Corporate');
        Test.stopTest();
        Map<String, Object> info = OnboardingController.getApiInfo();
        List<Onboarding_Application__c> apps = OnboardingController.getApplications();
        System.assertEquals('Retail', retail.Channel__c);
        System.assertEquals('Corporate', corp.Channel__c);
        System.assert(info.containsKey('healthUrl'));
        System.assert(apps.size() >= 2);
    }
}