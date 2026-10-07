@isTest
private class AccountStatementControllerTest {

    /**
     * Routes each callout to a canned response by path suffix, so a single
     * mock instance can serve the multiple calls a test may trigger.
     */
    private class RoutedMock implements HttpCalloutMock {
        private Map<String, String> responseByPathContains;
        private Integer statusCode;

        RoutedMock(Map<String, String> responseByPathContains, Integer statusCode) {
            this.responseByPathContains = responseByPathContains;
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            // Longer keys are more specific paths (e.g. "/transactions/export" vs.
            // "/transactions", or "/api/v1/accounts" which is a substring of every
            // path) - check those first so a generic key can't shadow a specific one.
            List<String> keysByLengthDesc = new List<String>(responseByPathContains.keySet());
            keysByLengthDesc.sort(new ByLengthDescending());
            for (String key : keysByLengthDesc) {
                if (req.getEndpoint().contains(key)) {
                    res.setBody(responseByPathContains.get(key));
                    return res;
                }
            }
            res.setStatusCode(404);
            res.setBody('{"code":"NOT_FOUND","message":"No mock configured for ' + req.getEndpoint() + '"}');
            return res;
        }
    }

    private class ByLengthDescending implements System.Comparator<String> {
        public Integer compare(String a, String b) {
            return b.length() - a.length();
        }
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
            LastName = 'TestUser',
            Email = 'portaltestuser' + uniqueSuffix + '@example.test',
            Username = 'portaltestuser' + uniqueSuffix + '@example.test',
            Alias = 'ptu' + uniqueSuffix.right(4),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
        try {
            insert portalUser;
        } catch (DmlException ex) {
            // This org's Digital Experiences settings don't yet allow creating users for this
            // profile outside of self-registration - covered by manual Phase 6 verification instead.
            return null;
        }
        return portalUser;
    }

    @isTest
    static void parseAccountListMapsAllFields() {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            '[{"accountId":"acc-1","accountNumber":"4000-1111","accountType":"Savings","balance":1234.56,"isPrimary":true}]'
        );

        List<AccountStatementController.BankAccountOption> options =
            AccountStatementController.parseAccountList(raw);

        System.assertEquals(1, options.size());
        System.assertEquals('acc-1', options[0].accountId);
        System.assertEquals('4000-1111', options[0].accountNumber);
        System.assertEquals('Savings', options[0].accountType);
        System.assertEquals(1234.56, options[0].balance);
        System.assertEquals(true, options[0].isPrimary);
    }

    @isTest
    static void parseOverviewHandlesNullDeltaFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"currentBalance":1000.00,"availableBalance":900.00,"balanceDeltaPercent":null,'
            + '"totalCredits":500.00,"creditCount":2,"totalDebits":100.00,"debitCount":1,'
            + '"totalFees":10.00,"feeCount":1,"closingBalance":1000.00,"closingBalanceDeltaPercent":null}'
        );

        AccountStatementController.StatementOverview overview = AccountStatementController.parseOverview(raw);

        System.assertEquals(1000.00, overview.currentBalance);
        System.assertEquals(900.00, overview.availableBalance);
        System.assertEquals(null, overview.balanceDeltaPercent);
        System.assertEquals(2, overview.creditCount);
        System.assertEquals(1, overview.debitCount);
        System.assertEquals(1, overview.feeCount);
        System.assertEquals(null, overview.closingBalanceDeltaPercent);
    }

    @isTest
    static void parseDashboardMapsPostgresPayload() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"accountId":"acc-1","accountNumber":"4000-1234-4587","lastFour":"4587",'
            + '"accountType":"Savings","isPrimary":true,"productTier":"Premium",'
            + '"ifsc":"LEVA0004587","branchName":"Anna Nagar, Chennai","openedOn":"2019-03-15",'
            + '"kycVerified":true,"currentBalance":256780.50,"availableBalance":248530.75,'
            + '"balanceDeltaPercent":12.4,"monthChange":27480,"pendingHolds":8249.75,'
            + '"lastCredit":150000,"todaySpend":2140,'
            + '"metrics":{"totalDeposits":482000,"totalDepositsTrendPercent":8.2,'
            + '"monthlyIncome":185000,"monthlyIncomeTrendPercent":3.1,'
            + '"monthlySpending":48320,"monthlySpendingTrendPercent":2.4,'
            + '"rewardsPoints":12480,"rewardsPointsDelta":640},'
            + '"trend":[{"monthLabel":"Apr","balance":256780.50}],'
            + '"spendCategories":[{"category":"BILLS","label":"Bills","amount":2140,"percent":22}],'
            + '"upcomingPayments":[{"paymentId":"p1","name":"Electricity - TNEB","dueDate":"2026-09-14","amount":2140,"category":"Bills"}],'
            + '"recentTransactions":[{"transactionId":"t1","transactionDate":"2026-09-09T00:00:00Z",'
            + '"description":"Salary Credit - Acme Corp","category":"Salary","recordType":"Credit","amount":150000,"status":"Completed"}],'
            + '"cards":[{"cardId":"c1","kind":"Debit","lastFour":"4587","status":"Active"}],'
            + '"investments":[{"investmentId":"i1","name":"FD · 12 Months","amount":150000}],'
            + '"goals":[{"goalId":"g1","name":"Emergency Fund","savedAmount":180000,"targetAmount":250000,"progressPercent":72}],'
            + '"insights":["Food spending dropped this month."],'
            + '"loan":{"productName":"Personal Loan","emiAmount":12480,"nextDueDate":"2026-10-05","status":"On Track"}}'
        );

        AccountStatementController.DashboardSnapshot snap = AccountStatementController.parseDashboard(raw);

        System.assertEquals('acc-1', snap.accountId);
        System.assertEquals('4587', snap.lastFour);
        System.assertEquals(248530.75, snap.availableBalance);
        System.assertEquals(12480, snap.metrics.rewardsPoints);
        System.assertEquals(1, snap.goals.size());
        System.assertEquals('Emergency Fund', snap.goals[0].name);
        System.assertEquals('Personal Loan', snap.loan.productName);
        System.assertEquals('Food spending dropped this month.', snap.insights[0]);
    }

    @isTest
    static void parseCashflowMapsSixPoints() {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            '[{"monthLabel":"Jan","credit":0,"debit":0},{"monthLabel":"Feb","credit":100.5,"debit":20.25}]'
        );

        List<AccountStatementController.CashflowPoint> points = AccountStatementController.parseCashflow(raw);

        System.assertEquals(2, points.size());
        System.assertEquals('Feb', points[1].monthLabel);
        System.assertEquals(100.5, points[1].credit);
        System.assertEquals(20.25, points[1].debit);
    }

    @isTest
    static void parseTransactionPageMapsRowsAndTotalCount() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"rows":[{"transactionId":"t-1","referenceNumber":"TXN-1","transactionDate":"2026-01-15T10:00:00Z",'
            + '"description":"Groceries","category":"Shopping","recordType":"Debit","amount":42.10,'
            + '"runningBalance":957.90,"status":"Completed"}],"totalCount":3}'
        );

        AccountStatementController.TransactionPage page = AccountStatementController.parseTransactionPage(raw);

        System.assertEquals(3, page.totalCount);
        System.assertEquals(1, page.rows.size());
        System.assertEquals('TXN-1', page.rows[0].referenceNumber);
        System.assertEquals('2026-01-15T10:00:00Z', page.rows[0].transactionDate);
        System.assertEquals(42.10, page.rows[0].amount);
    }

    @isTest
    static void parseFraudFlagsMapsAllFields() {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            '[{"transactionId":"t-1","transactionDate":"2026-01-15T10:00:00Z","amount":4200.00,'
            + '"reason":"Amount is unusually high compared to this account\'s typical spending.","severity":"HIGH"}]'
        );

        List<AccountStatementController.FraudFlag> flags = AccountStatementController.parseFraudFlags(raw);

        System.assertEquals(1, flags.size());
        System.assertEquals('t-1', flags[0].transactionId);
        System.assertEquals(4200.00, flags[0].amount);
        System.assertEquals('HIGH', flags[0].severity);
    }

    @isTest
    static void publicMethodsThrowWhenRunningUserHasNoLinkedContact() {
        Date today = Date.today();

        Test.startTest();
        Integer exceptionCount = 0;

        try {
            AccountStatementController.getMyAccounts();
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getStatementOverview('some-account-id', today, today);
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getMonthlyCashflow('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getTransactions('some-account-id', today, today, 'All', null, 1, 10);
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getTransactionsForExport('some-account-id', today, today, 'All', null);
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getInsights('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getFraudFlags('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AccountStatementController.getDashboard('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        Test.stopTest();

        System.assertEquals(8, exceptionCount, 'Every public method should require a linked Contact and surface it as an AuraHandledException');
    }

    @isTest
    static void portalUserReceivesParsedDataFromJavaApiEndToEnd() {
        Contact contact = createPortalContact('Portal Statement Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // see createPortalUser - environment doesn't allow portal user creation
        }

        Test.setMock(HttpCalloutMock.class, new RoutedMock(
            new Map<String, String>{
                '/statement-overview' => '{}',
                '/monthly-cashflow' => '[]',
                '/transactions/export' => '[]',
                '/transactions' => '{"rows":[],"totalCount":0}',
                '/api/v1/accounts' =>
                    '[{"accountId":"acc-1","accountNumber":"4000-1111","accountType":"Savings","balance":500.00,"isPrimary":true}]'
            },
            200
        ));

        Test.startTest();
        System.runAs(portalUser) {
            List<AccountStatementController.BankAccountOption> accounts = AccountStatementController.getMyAccounts();
            System.assertEquals(1, accounts.size());
            System.assertEquals('acc-1', accounts[0].accountId);
            System.assertEquals(500.00, accounts[0].balance);
        }
        Test.stopTest();
    }

    @isTest
    static void portalUserSeesJavaApiErrorAsAuraHandledException() {
        Contact contact = createPortalContact('Portal Error Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // see createPortalUser - environment doesn't allow portal user creation
        }

        Test.setMock(HttpCalloutMock.class, new RoutedMock(
            new Map<String, String>{
                '/statement-overview' => '{"code":"UNAUTHORIZED_ACCOUNT","message":"This account does not belong to the current user."}'
            },
            403
        ));

        Test.startTest();
        System.runAs(portalUser) {
            Boolean threw = false;
            try {
                AccountStatementController.getStatementOverview('someone-elses-account', Date.today(), Date.today());
            } catch (AuraHandledException ex) {
                threw = true;
                System.assertEquals('This account does not belong to the current user.', ex.getMessage());
            }
            System.assert(threw, 'Expected the Java API error to surface as an AuraHandledException');
        }
        Test.stopTest();
    }
}