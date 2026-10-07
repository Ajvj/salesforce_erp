@IsTest
private class EngageIQServiceTest {
    class GeoMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"country_name":"India","region":"Tamil Nadu","city":"Chennai","latitude":13.08,"longitude":80.27,"timezone":"Asia/Kolkata","org":"Example ISP"}'
            );
            return res;
        }
    }

    static void rest(String uri, String method, String body, String ip) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = method;
        req.remoteAddress = ip;
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @IsTest
    static void liveVisitChatAndLead() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        rest(
            '/services/apexrest/visitor/track',
            'POST',
            '{"visitorKey":"v-live-1","pageUrl":"https://bank.example/home","referrer":"https://google.com","userAgent":"Mozilla/5.0","language":"en-IN","timezone":"Asia/Kolkata"}',
            '8.8.8.8'
        );
        Test.startTest();
        EngageIQVisitorRest.doPost();
        Map<String, Object> tracked = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        rest(
            '/services/apexrest/chat/start',
            'POST',
            '{"visitorKey":"v-live-1","pageUrl":"https://bank.example/home"}',
            '8.8.8.8'
        );
        EngageIQChatRest.doPost();
        Map<String, Object> started = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        Id transcriptId = (Id) started.get('transcriptId');
        rest(
            '/services/apexrest/chat/message',
            'POST',
            JSON.serialize(new Map<String, Object>{ 'transcriptId' => transcriptId, 'body' => 'I want a savings account' }),
            '8.8.8.8'
        );
        EngageIQChatRest.doPost();
        Test.stopTest();

        EngageIQ_Visitor__c visitor = [
            SELECT IP_Address__c, City__c, Country__c, Status__c FROM EngageIQ_Visitor__c WHERE Visitor_Key__c = 'v-live-1'
        ];
        System.assertEquals('8.8.8.8', visitor.IP_Address__c);
        System.assertEquals('Chennai', visitor.City__c);
        System.assertEquals('India', visitor.Country__c);

        Map<String, Object> inbox = EngageIQController.sendAgentMessage(transcriptId, 'Yes, we can help you open it.');
        System.assertNotEquals(null, inbox.get('conversationId'));

        Map<String, Object> converted = EngageIQController.captureLead(
            transcriptId,
            visitor.Id,
            'Priya Raman',
            'priya@example.com',
            '9876543210',
            'Retail banking'
        );
        Test.getEventBus().deliver();
        visitor = [
            SELECT Status__c, Lead__c FROM EngageIQ_Visitor__c WHERE Visitor_Key__c = 'v-live-1'
        ];
        System.assertEquals('Converted', visitor.Status__c);
        System.assertNotEquals(null, visitor.Lead__c);
        System.assertNotEquals(null, converted.get('conversationId'));

        Map<String, Object> home = EngageIQController.loadHome(null);
        System.assert((Integer) home.get('visitorCount') >= 1);
        System.assert((Integer) home.get('convertedCount') >= 1);
        List<EngageIQ_Audit__c> events = [SELECT Event_Type__c FROM EngageIQ_Audit__c];
        System.assert(events.size() >= 4, 'Audit trail should capture visit, chat, messages, and lead');
    }

    @IsTest
    static void convertVisitorWithoutChat() {
        Test.startTest();
        Map<String, Object> tracked = EngageIQService.track(
            '{"visitorKey":"v-lead-only","pageUrl":"https://bank.example/rates"}'
        );
        Id visitorId = (Id) tracked.get('visitorId');
        EngageIQController.captureLead(null, visitorId, 'Arun Kumar', 'arun@example.com', '9000000000', 'NRI');
        Test.stopTest();
        EngageIQ_Visitor__c visitor = [
            SELECT Status__c, Lead__c, Email__c FROM EngageIQ_Visitor__c WHERE Id = :visitorId
        ];
        System.assertEquals('Converted', visitor.Status__c);
        System.assertEquals('arun@example.com', visitor.Email__c);
        System.assertNotEquals(null, visitor.Lead__c);
    }

    @IsTest
    static void pollMessagesAndAssign() {
        Map<String, Object> started = EngageIQService.startChat(
            '{"visitorKey":"v-poll","pageUrl":"https://bank.example/loans"}'
        );
        Id transcriptId = (Id) started.get('transcriptId');
        EngageIQService.postMessage(
            JSON.serialize(new Map<String, Object>{ 'transcriptId' => transcriptId, 'body' => 'Need a home loan' }),
            'Visitor',
            null
        );
        Test.startTest();
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/chat/messages';
        req.httpMethod = 'GET';
        req.params.put('transcriptId', String.valueOf(transcriptId));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        EngageIQChatRest.doGet();
        EngageIQController.assignToMe(transcriptId);
        EngageIQController.closeConversation(transcriptId);
        Test.stopTest();
        List<Object> messages = (List<Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assert(messages.size() >= 2);
        EngageIQ_Conversation__c convo = [SELECT Status__c FROM EngageIQ_Conversation__c WHERE Id = :transcriptId];
        System.assertEquals('Closed', convo.Status__c);
    }

    @IsTest
    static void twoWebsitesStaySeparate() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        Map<String, Object> retail = EngageIQController.saveWebsite(
            null,
            'Retail banking',
            'https://www.retailbank.com',
            'Active'
        );
        Map<String, Object> nri = EngageIQController.saveWebsite(
            null,
            'NRI banking',
            'nri.bank.com',
            'Active'
        );
        Map<String, Object> retailSite = (Map<String, Object>) retail.get('website');
        Map<String, Object> nriSite = (Map<String, Object>) nri.get('website');
        System.assertEquals('retailbank.com', EngageIQService.normalizeHost('https://www.retailbank.com/loans'));
        System.assertNotEquals(retailSite.get('Site_Key__c'), nriSite.get('Site_Key__c'));

        EngageIQService.track(
            JSON.serialize(
                new Map<String, Object>{
                    'visitorKey' => 'v-retail',
                    'pageUrl' => 'https://www.retailbank.com/home',
                    'siteKey' => retailSite.get('Site_Key__c')
                }
            )
        );
        EngageIQService.track(
            JSON.serialize(
                new Map<String, Object>{
                    'visitorKey' => 'v-nri',
                    'pageUrl' => 'https://nri.bank.com/nri-deposits',
                    'siteKey' => nriSite.get('Site_Key__c')
                }
            )
        );

        EngageIQ_Visitor__c retailVisitor = [
            SELECT Website__c FROM EngageIQ_Visitor__c WHERE Visitor_Key__c = 'v-retail'
        ];
        EngageIQ_Visitor__c nriVisitor = [
            SELECT Website__c FROM EngageIQ_Visitor__c WHERE Visitor_Key__c = 'v-nri'
        ];
        System.assertEquals((Id) retailSite.get('Id'), retailVisitor.Website__c);
        System.assertEquals((Id) nriSite.get('Id'), nriVisitor.Website__c);

        Map<String, Object> retailHome = EngageIQController.loadHome((Id) retailSite.get('Id'));
        System.assertEquals(1, (Integer) retailHome.get('visitorCount'));
        Map<String, Object> listed = EngageIQController.listWebsites();
        System.assertEquals(2, (Integer) listed.get('websiteCount'));
        System.assertNotEquals(null, retailSite.get('embedSnippet'));
        System.assertEquals('#3d1466', EngageIQService.normalizeHexColor('#3D1466'));
        System.assertEquals('#3d1466', listed.get('brandColor'));
        Map<String, Object> themed = EngageIQController.saveBrandColor('#0E7C66');
        System.assertEquals('#0e7c66', themed.get('brandColor'));
        System.assertEquals('#0e7c66', EngageIQService.brandColor());
        Boolean badColor = false;
        try {
            EngageIQController.saveBrandColor('purple');
        } catch (AuraHandledException e) {
            badColor = true;
        }
        System.assert(badColor);

        Map<String, Object> deactivated = EngageIQController.setWebsiteStatus((Id) nriSite.get('Id'), 'Inactive');
        System.assertEquals(1, (Integer) deactivated.get('inactiveCount'));
        EngageIQController.setWebsiteStatus((Id) nriSite.get('Id'), 'Active');

        rest('/services/apexrest/visitor/ping', 'GET', null, '8.8.8.8');
        EngageIQVisitorRest.doGet();
        rest('/services/apexrest/visitor/unknown', 'POST', '{}', '8.8.8.8');
        EngageIQVisitorRest.doPost();
        rest('/services/apexrest/chat/unknown', 'POST', '{}', '8.8.8.8');
        EngageIQChatRest.doPost();
        rest('/services/apexrest/chat/other', 'GET', null, '8.8.8.8');
        EngageIQChatRest.doGet();
        Boolean savedBlank = false;
        try {
            EngageIQController.saveWebsite(null, '', 'missing.com', 'Active');
        } catch (AuraHandledException e) {
            savedBlank = true;
        }
        System.assert(savedBlank);
        Boolean statusFailed = false;
        try {
            EngageIQController.setWebsiteStatus(null, 'Active');
        } catch (AuraHandledException e) {
            statusFailed = true;
        }
        System.assert(statusFailed);
        Boolean assignFailed = false;
        try {
            EngageIQController.assignToMe(null);
        } catch (AuraHandledException e) {
            assignFailed = true;
        }
        System.assert(assignFailed);
        Boolean closeFailed = false;
        try {
            EngageIQController.closeConversation(null);
        } catch (AuraHandledException e) {
            closeFailed = true;
        }
        System.assert(closeFailed);
        Boolean leadFailed = false;
        try {
            EngageIQController.captureLead(null, null, null, null, null, null);
        } catch (AuraHandledException e) {
            leadFailed = true;
        }
        System.assert(leadFailed);
        EngageIQController.loadInbox(null);
    }
}