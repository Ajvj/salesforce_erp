@isTest
private class StatementPdfControllerTest {

    private class RoutedMock implements HttpCalloutMock {
        private Map<String, String> responseByPathContains;

        RoutedMock(Map<String, String> responseByPathContains) {
            this.responseByPathContains = responseByPathContains;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            // Longer keys are more specific paths (e.g. ".../transactions/export"
            // vs. "/api/v1/accounts", which is a substring of it) - check those first
            // so a generic key can't shadow a more specific one.
            List<String> keysByLengthDesc = new List<String>(responseByPathContains.keySet());
            keysByLengthDesc.sort(new ByLengthDescending());
            for (String key : keysByLengthDesc) {
                if (req.getEndpoint().contains(key)) {
                    res.setBody(responseByPathContains.get(key));
                    return res;
                }
            }
            res.setStatusCode(404);
            res.setBody('{"code":"NOT_FOUND","message":"No mock configured"}');
            return res;
        }
    }

    private class ByLengthDescending implements System.Comparator<String> {
        public Integer compare(String a, String b) {
            return b.length() - a.length();
        }
    }

    @isTest
    static void constructorThrowsWhenCurrentUserHasNoLinkedContact() {
        Test.setCurrentPageReference(new PageReference('/apex/StatementPdf'));
        ApexPages.currentPage().getParameters().put('accountId', 'some-account-id');

        Test.startTest();
        Boolean threw = false;
        try {
            new StatementPdfController();
        } catch (BankAccountSelector.NoLinkedContactException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected an exception since the running admin has no linked Contact');
    }

    @isTest
    static void constructorThrowsWhenAccountIsNotOwnedByCurrentUser() {
        Contact contact = createPortalContact('PDF Isolation Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // environment doesn't allow portal user creation - see createPortalUser
        }

        Test.setCurrentPageReference(new PageReference('/apex/StatementPdf'));
        ApexPages.currentPage().getParameters().put('accountId', 'someone-elses-account');

        Test.setMock(HttpCalloutMock.class, new RoutedMock(new Map<String, String>{
            '/api/v1/accounts' => '[]'
        }));

        Test.startTest();
        System.runAs(portalUser) {
            Boolean threw = false;
            try {
                new StatementPdfController();
            } catch (StatementPdfController.UnauthorizedAccountException ex) {
                threw = true;
            }
            System.assert(threw, 'Expected an UnauthorizedAccountException for an account the Java API does not return');
        }
        Test.stopTest();
    }

    @isTest
    static void constructorPopulatesAccountAndTransactionsForOwnedAccount() {
        Contact contact = createPortalContact('PDF Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // environment doesn't allow portal user creation - see createPortalUser
        }

        Test.setCurrentPageReference(new PageReference('/apex/StatementPdf'));
        ApexPages.currentPage().getParameters().put('accountId', 'acc-1');
        ApexPages.currentPage().getParameters().put('startDate', '2026-01-01');
        ApexPages.currentPage().getParameters().put('endDate', '2026-01-31');

        Test.setMock(HttpCalloutMock.class, new RoutedMock(new Map<String, String>{
            '/api/v1/accounts' =>
                '[{"accountId":"acc-1","accountNumber":"4000-1111","accountType":"Savings","balance":500.00,"isPrimary":true}]',
            '/transactions/export' =>
                '[{"transactionId":"t-1","referenceNumber":"TXN-1","transactionDate":"2026-01-15T10:00:00Z",'
                + '"description":"Groceries","category":"Shopping","recordType":"Debit","amount":42.10,'
                + '"runningBalance":457.90,"status":"Completed"}]'
        }));

        Test.startTest();
        System.runAs(portalUser) {
            StatementPdfController controller = new StatementPdfController();
            System.assertEquals('4000-1111', controller.accountNumber);
            System.assertEquals('Savings', controller.accountType);
            System.assertEquals(500.00, controller.balance);
            System.assertEquals(1, controller.transactions.size());
            System.assertEquals('TXN-1', controller.transactions[0].referenceNumber);
            System.assertEquals(42.10, controller.transactions[0].amount);
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
            LastName = 'PdfTestUser',
            Email = 'portalpdftestuser' + uniqueSuffix + '@example.test',
            Username = 'portalpdftestuser' + uniqueSuffix + '@example.test',
            Alias = 'ppdf' + uniqueSuffix.right(4),
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