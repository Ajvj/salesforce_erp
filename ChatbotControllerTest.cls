@isTest
private class ChatbotControllerTest {

    private class RoutedMock implements HttpCalloutMock {
        private String responseBody;
        private Integer statusCode;

        RoutedMock(String responseBody, Integer statusCode) {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('POST', req.getMethod());
            System.assert(
                req.getEndpoint().endsWith('/chat') || req.getEndpoint().endsWith('/analyze-document-base64'),
                req.getEndpoint()
            );

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    @isTest
    static void parseDocumentAnalysisMapsExtractedFields() {
        Map<String, Object> raw = new Map<String, Object>{
            'extractedText' => 'PAN ABCDE1234F salary Rs. 85000',
            'fields' => new Map<String, Object>{
                'pan' => 'ABCDE1234F',
                'email' => 'hr@example.com',
                'amounts_found' => new List<Object>{ '85000' },
                'dates_found' => new List<Object>{ '01/08/2026' }
            }
        };

        ChatbotController.DocumentAnalysisResult result = ChatbotController.parseDocumentAnalysis(raw);

        System.assertEquals('ABCDE1234F', result.pan);
        System.assertEquals('hr@example.com', result.email);
        System.assertEquals(1, result.amounts.size());
        System.assertEquals('01/08/2026', result.dates[0]);
    }

    @isTest
    static void parseDocumentAnalysisHandlesMissingFields() {
        ChatbotController.DocumentAnalysisResult result = ChatbotController.parseDocumentAnalysis(
            new Map<String, Object>{ 'extractedText' => 'plain text' }
        );
        System.assertEquals('plain text', result.extractedText);
        System.assertEquals(0, result.amounts.size());
        System.assertEquals(0, result.dates.size());
    }

    @isTest
    static void analyzeDocumentThrowsWhenRunningUserHasNoLinkedContact() {
        Test.setMock(HttpCalloutMock.class, new RoutedMock('{"extractedText":"x","fields":{}}', 200));

        Test.startTest();
        Boolean threw = false;
        try {
            ChatbotController.analyzeDocument('slip.png', 'ZmFrZQ==');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected the no-linked-contact path to surface as an AuraHandledException');
    }

    @isTest
    static void portalUserReceivesDocumentAnalysisFromChatbotService() {
        Contact contact = createPortalContact('Document Success Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return;
        }

        Test.setMock(
            HttpCalloutMock.class,
            new RoutedMock('{"extractedText":"PAN ABCDE1234F","fields":{"pan":"ABCDE1234F"}}', 200)
        );

        Test.startTest();
        System.runAs(portalUser) {
            ChatbotController.DocumentAnalysisResult result = ChatbotController.analyzeDocument('pan.png', 'ZmFrZQ==');
            System.assertEquals('ABCDE1234F', result.pan);
            System.assertEquals('PAN ABCDE1234F', result.extractedText);
        }
        Test.stopTest();
    }

    @isTest
    static void sendMessageThrowsWhenRunningUserHasNoLinkedContact() {
        Test.setMock(HttpCalloutMock.class, new RoutedMock('{"reply":"hi"}', 200));

        Test.startTest();
        Boolean threw = false;
        try {
            ChatbotController.sendMessage('What is my balance?');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected the no-linked-contact path to surface as an AuraHandledException');
    }

    @isTest
    static void portalUserReceivesReplyFromChatbotService() {
        Contact contact = createPortalContact('Chatbot Success Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // environment doesn't allow portal user creation - see createPortalUser
        }

        Test.setMock(HttpCalloutMock.class, new RoutedMock('{"reply":"Your balance is $500."}', 200));

        Test.startTest();
        System.runAs(portalUser) {
            String reply = ChatbotController.sendMessage('What is my balance?');
            System.assertEquals('Your balance is $500.', reply);
        }
        Test.stopTest();
    }

    @isTest
    static void portalUserSeesUpstreamErrorAsAuraHandledException() {
        Contact contact = createPortalContact('Chatbot Error Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // environment doesn't allow portal user creation - see createPortalUser
        }

        Test.setMock(HttpCalloutMock.class, new RoutedMock('service unavailable', 503));

        Test.startTest();
        System.runAs(portalUser) {
            Boolean threw = false;
            try {
                ChatbotController.sendMessage('Hello');
            } catch (AuraHandledException ex) {
                threw = true;
                System.assert(ex.getMessage().contains('503'));
            }
            System.assert(threw, 'Expected the upstream failure to surface as an AuraHandledException');
        }
        Test.stopTest();
    }

    private static Contact createPortalContact(String lastName) {
        Account biz = new Account(Name = lastName + ' Business Account', OwnerId = UserInfo.getUserId());
        insert biz;
        Contact contact = new Contact(LastName = lastName, AccountId = biz.Id);
        insert contact;
        return contact;
    }

    private static User createPortalUser(Contact contact) {
        List<Profile> portalProfiles = [
            SELECT Id
            FROM Profile
            WHERE UserLicense.Name IN ('Customer Community Plus', 'Customer Community', 'Customer Community Login')
            LIMIT 1
        ];
        if (portalProfiles.isEmpty()) {
            return null;
        }
        String uniqueSuffix = String.valueOf(Datetime.now().getTime()) + Math.round(Math.random() * 1000);
        User portalUser = new User(
            ProfileId = portalProfiles[0].Id,
            ContactId = contact.Id,
            FirstName = 'Portal',
            LastName = 'ChatbotTestUser',
            Email = 'portalchatbottestuser' + uniqueSuffix + '@example.test',
            Username = 'portalchatbottestuser' + uniqueSuffix + '@example.test',
            Alias = 'pcbt' + uniqueSuffix.right(4),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        try {
            insert portalUser;
        } catch (DmlException ex) {
            return null;
        }
        return portalUser;
    }
}