@isTest
private class FundTransferControllerTest {

    private class RoutedMock implements HttpCalloutMock {
        private String responseBody;
        private Integer statusCode;

        RoutedMock(String responseBody, Integer statusCode) {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('POST', req.getMethod(), 'Transfer should be a POST request');
            System.assertEquals('application/json', req.getHeader('Content-Type'));

            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    @isTest
    static void transferFundsThrowsWhenRunningUserHasNoLinkedContact() {
        Test.setMock(HttpCalloutMock.class, new RoutedMock('{}', 200));

        Test.startTest();
        Boolean threw = false;
        try {
            FundTransferController.transferFunds('some-account-id', '4000-0000-0002', 50.00, 'Test');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected the no-linked-contact path to surface as an AuraHandledException');
    }

    @isTest
    static void parseResultMapsAllFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"transactionId":"t-1","referenceNumber":"TXN-XFER-ABC12345","newBalance":450.00,"status":"Completed"}'
        );

        FundTransferController.TransferResult result = FundTransferController.parseResult(raw);

        System.assertEquals('t-1', result.transactionId);
        System.assertEquals('TXN-XFER-ABC12345', result.referenceNumber);
        System.assertEquals(450.00, result.newBalance);
        System.assertEquals('Completed', result.status);
    }
}