@isTest
private class AiCopilotControllerTest {

    /**
     * Routes each callout to a canned response by path suffix, so a single
     * mock instance can serve the multiple GET endpoints one end-to-end test
     * exercises in sequence.
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
            // profile outside of self-registration - covered by manual verification instead.
            return null;
        }
        return portalUser;
    }

    @isTest
    static void portalUserReceivesReadOnlyInsightsEndToEnd() {
        Contact contact = createPortalContact('Portal Guardrail Customer');
        User portalUser = createPortalUser(contact);
        if (portalUser == null) {
            return; // see createPortalUser - environment doesn't allow portal user creation
        }

        Test.setMock(HttpCalloutMock.class, new RoutedMock(
            new Map<String, String>{
                '/low-balance-warnings' =>
                    '{"alerts":[{"paymentName":"Electricity","category":"Bills","dueDate":"2026-09-20",'
                    + '"amountDue":500,"projectedBalanceBeforePayment":300,"projectedBalanceAfterPayment":-200,'
                    + '"willFail":true,"shortfallAmount":200,"recommendedAction":"Add at least 200.00"}],'
                    + '"summary":"1 of 1 upcoming payments in the next 30 days are at risk of failing."}',
                '/idle-funds' =>
                    '{"idle":true,"currentBalance":100000,"averageMonthlySpend":5000,'
                    + '"recommendedFdAmount":90000,"estimatedAnnualGain":4500,"explanation":"move it"}',
                '/forecast' =>
                    '{"points":[{"date":"2026-09-10","projectedBalance":1000}],'
                    + '"safetyFloor":500,"firstBreachDate":null,"explanation":"stable"}',
                '/goals' => '[{"id":"g-1","name":"Trip","targetAmount":300000,"savedAmount":50000,'
                    + '"targetDate":"2028-01-01","requiredMonthlyContribution":20000,'
                    + '"progressPercent":16.7,"onTrack":true}]',
                '/disputes' => '[{"id":"d-1","transactionId":"t-1","description":"unknown charge",'
                    + '"status":"CARD_BLOCKED","statusSteps":["IDENTIFIED","CARD_BLOCKED"],'
                    + '"createdAt":"2026-09-10T00:00:00Z","updatedAt":"2026-09-10T00:00:00Z"}]',
                '/life-events' => '[{"type":"INCOME_CHANGE","description":"salary rose","detectedDate":"2026-09-10"}]',
                '/spend-prediction' => '{"categories":[{"category":"Shopping","predictedAmount":233.33,'
                    + '"lastMonthAmount":300.00,"trend":"Rising","monthsOfHistory":3}],"totalPredicted":233.33,'
                    + '"explanation":"Based on the last 3 months, you are likely to spend about 233.33 next month, led by Shopping."}',
                '/category-suggestions/apply' => '{"transactionId":"t-1","description":"Swiggy Order #4521",'
                    + '"currentCategory":"Other","suggestedCategory":"Food_Dining","matchedKeyword":null}',
                '/category-suggestions' => '{"suggestions":[{"transactionId":"t-1","description":"Swiggy Order #4521",'
                    + '"currentCategory":"Other","suggestedCategory":"Food_Dining","matchedKeyword":"swiggy"}],'
                    + '"explanation":"Found 1 transaction(s) in \\"Other\\" that look like they belong in a different category, based on their description."}'
            },
            200
        ));

        Test.startTest();
        System.runAs(portalUser) {
            AiCopilotController.LowBalanceWarningResult lowBalance = AiCopilotController.getLowBalanceWarnings('some-account-id');
            System.assertEquals(1, lowBalance.alerts.size());
            System.assertEquals(true, lowBalance.alerts[0].willFail);

            AiCopilotController.IdleFundsInsight idle = AiCopilotController.getIdleFunds('some-account-id');
            System.assertEquals(true, idle.idle);

            AiCopilotController.ForecastResult forecast = AiCopilotController.getForecast('some-account-id', 30);
            System.assertEquals(1, forecast.points.size());

            List<AiCopilotController.SavingsGoal> goals = AiCopilotController.getGoals('some-account-id');
            System.assertEquals(1, goals.size());
            System.assertEquals('Trip', goals[0].name);

            List<AiCopilotController.DisputeRecord> disputes = AiCopilotController.getDisputes('some-account-id');
            System.assertEquals(1, disputes.size());

            List<AiCopilotController.LifeEvent> events = AiCopilotController.getLifeEvents('some-account-id');
            System.assertEquals(1, events.size());

            AiCopilotController.SpendPredictionResult spendPrediction = AiCopilotController.getSpendPrediction('some-account-id');
            System.assertEquals(1, spendPrediction.categories.size());
            System.assertEquals('Rising', spendPrediction.categories[0].trend);

            AiCopilotController.AutoCategorizationResult categorySuggestions = AiCopilotController.getCategorySuggestions('some-account-id');
            System.assertEquals(1, categorySuggestions.suggestions.size());
            System.assertEquals('Food_Dining', categorySuggestions.suggestions[0].suggestedCategory);

            AiCopilotController.CategorySuggestion applied = AiCopilotController.applyCategorySuggestion(
                'some-account-id', 't-1', 'Food_Dining');
            System.assertEquals('Food_Dining', applied.suggestedCategory);
        }
        Test.stopTest();
    }

    @isTest
    static void parseLoanResultMapsAllFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"estimatedMonthlyIncome":30000,"averageMonthlySpend":6500,"requestedEmi":17000,'
            + '"remainingAfterRequestedEmi":6500,"emiBurdenPercentOfIncome":56.7,"withinRecommendedBurden":false,'
            + '"recommendedSaferLoanAmount":1500000,"recommendedSaferEmi":12000,"explanation":"too tight"}'
        );
        AiCopilotController.LoanAffordabilityResult result = AiCopilotController.parseLoanResult(raw);
        System.assertEquals(false, result.withinRecommendedBurden);
        System.assertEquals(1500000, result.recommendedSaferLoanAmount);
    }

    @isTest
    static void parseIdleFundsMapsAllFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"idle":true,"currentBalance":100000,"averageMonthlySpend":5000,'
            + '"recommendedFdAmount":90000,"estimatedAnnualGain":4500,"explanation":"move it"}'
        );
        AiCopilotController.IdleFundsInsight insight = AiCopilotController.parseIdleFunds(raw);
        System.assertEquals(true, insight.idle);
        System.assertEquals(90000, insight.recommendedFdAmount);
    }

    @isTest
    static void parseForecastMapsPointsAndBreach() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"points":[{"date":"2026-09-10","projectedBalance":1000},{"date":"2026-09-11","projectedBalance":900}],'
            + '"safetyFloor":500,"firstBreachDate":null,"explanation":"stable"}'
        );
        AiCopilotController.ForecastResult result = AiCopilotController.parseForecast(raw);
        System.assertEquals(2, result.points.size());
        System.assertEquals(900, result.points[1].projectedBalance);
    }

    @isTest
    static void parseGoalMapsAllFields() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"id":"g-1","name":"Trip","targetAmount":300000,"savedAmount":50000,"targetDate":"2028-01-01",'
            + '"requiredMonthlyContribution":20000,"progressPercent":16.7,"onTrack":true}'
        );
        AiCopilotController.SavingsGoal goal = AiCopilotController.parseGoal(raw);
        System.assertEquals('Trip', goal.name);
        System.assertEquals(true, goal.onTrack);
    }

    @isTest
    static void parseDisputeMapsStatusSteps() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"id":"d-1","transactionId":"t-1","description":"unknown charge","status":"CARD_BLOCKED",'
            + '"statusSteps":["IDENTIFIED","CARD_BLOCKED"],"createdAt":"2026-09-10T00:00:00Z","updatedAt":"2026-09-10T00:00:00Z"}'
        );
        AiCopilotController.DisputeRecord dispute = AiCopilotController.parseDispute(raw);
        System.assertEquals(2, dispute.statusSteps.size());
        System.assertEquals('CARD_BLOCKED', dispute.status);
    }

    @isTest
    static void parseLifeEventsMapsAllFields() {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(
            '[{"type":"INCOME_CHANGE","description":"salary rose","detectedDate":"2026-09-10"}]'
        );
        List<AiCopilotController.LifeEvent> events = AiCopilotController.parseLifeEvents(raw);
        System.assertEquals(1, events.size());
        System.assertEquals('INCOME_CHANGE', events[0].eventType);
    }

    @isTest
    static void parseLowBalanceWarningResultMapsAlertsAndSummary() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"alerts":[{"paymentName":"Electricity","category":"Bills","dueDate":"2026-09-20",'
            + '"amountDue":500,"projectedBalanceBeforePayment":300,"projectedBalanceAfterPayment":-200,'
            + '"willFail":true,"shortfallAmount":200,"recommendedAction":"Add at least 200.00"}],'
            + '"summary":"1 of 1 upcoming payments in the next 30 days are at risk of failing."}'
        );
        AiCopilotController.LowBalanceWarningResult result = AiCopilotController.parseLowBalanceWarningResult(raw);
        System.assertEquals(1, result.alerts.size());
        System.assertEquals(true, result.alerts[0].willFail);
        System.assertEquals(200, result.alerts[0].shortfallAmount);
        System.assertEquals('Electricity', result.alerts[0].paymentName);
    }

    @isTest
    static void parseSpendPredictionMapsCategoriesAndTotal() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"categories":[{"category":"Shopping","predictedAmount":233.33,"lastMonthAmount":300.00,'
            + '"trend":"Rising","monthsOfHistory":3}],"totalPredicted":233.33,'
            + '"explanation":"Based on the last 3 months, you are likely to spend about 233.33 next month, led by Shopping."}'
        );
        AiCopilotController.SpendPredictionResult result = AiCopilotController.parseSpendPrediction(raw);
        System.assertEquals(1, result.categories.size());
        System.assertEquals('Shopping', result.categories[0].category);
        System.assertEquals('Rising', result.categories[0].trend);
        System.assertEquals(233.33, result.totalPredicted);
    }

    @isTest
    static void parseAutoCategorizationResultMapsSuggestions() {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
            '{"suggestions":[{"transactionId":"t-1","description":"Swiggy Order #4521","currentCategory":"Other",'
            + '"suggestedCategory":"Food_Dining","matchedKeyword":"swiggy"}],'
            + '"explanation":"Found 1 transaction(s) in \\"Other\\" that look like they belong in a different category, based on their description."}'
        );
        AiCopilotController.AutoCategorizationResult result = AiCopilotController.parseAutoCategorizationResult(raw);
        System.assertEquals(1, result.suggestions.size());
        System.assertEquals('Food_Dining', result.suggestions[0].suggestedCategory);
        System.assertEquals('swiggy', result.suggestions[0].matchedKeyword);
    }

    @isTest
    static void publicMethodsThrowWhenRunningUserHasNoLinkedContact() {
        Test.startTest();
        Integer exceptionCount = 0;

        try {
            AiCopilotController.checkLoanAffordability('some-account-id', 100000, 5, 8.5);
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getIdleFunds('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getForecast('some-account-id', 30);
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getGoals('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.createGoal('some-account-id', 'Trip', 100000, '2028-01-01');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getDisputes('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.fileDispute('some-account-id', null, 'unknown charge');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getLifeEvents('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getLowBalanceWarnings('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getSpendPrediction('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.getCategorySuggestions('some-account-id');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        try {
            AiCopilotController.applyCategorySuggestion('some-account-id', 't-1', 'Food_Dining');
        } catch (AuraHandledException ex) {
            exceptionCount++;
        }
        Test.stopTest();

        System.assertEquals(12, exceptionCount, 'Every public method should require a linked Contact and surface it as an AuraHandledException');
    }
}