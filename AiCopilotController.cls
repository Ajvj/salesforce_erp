/**
 * Thin proxy to the Java "AI copilot" endpoints (loan affordability, idle
 * funds, cash-flow forecast, savings goals, disputes, life-event detection).
 * Same pattern as every other controller here - Apex forwards, Java decides.
 */
public with sharing class AiCopilotController {

    public class LoanAffordabilityResult {
        @AuraEnabled public Decimal estimatedMonthlyIncome;
        @AuraEnabled public Decimal averageMonthlySpend;
        @AuraEnabled public Decimal requestedEmi;
        @AuraEnabled public Decimal remainingAfterRequestedEmi;
        @AuraEnabled public Decimal emiBurdenPercentOfIncome;
        @AuraEnabled public Boolean withinRecommendedBurden;
        @AuraEnabled public Decimal recommendedSaferLoanAmount;
        @AuraEnabled public Decimal recommendedSaferEmi;
        @AuraEnabled public String explanation;
    }

    public class IdleFundsInsight {
        @AuraEnabled public Boolean idle;
        @AuraEnabled public Decimal currentBalance;
        @AuraEnabled public Decimal averageMonthlySpend;
        @AuraEnabled public Decimal recommendedFdAmount;
        @AuraEnabled public Decimal estimatedAnnualGain;
        @AuraEnabled public String explanation;
    }

    public class ForecastPoint {
        @AuraEnabled public String forecastDate;
        @AuraEnabled public Decimal projectedBalance;
    }

    public class ForecastResult {
        @AuraEnabled public List<ForecastPoint> points;
        @AuraEnabled public Decimal safetyFloor;
        @AuraEnabled public String firstBreachDate;
        @AuraEnabled public String explanation;
    }

    public class SavingsGoal {
        @AuraEnabled public String goalId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Decimal savedAmount;
        @AuraEnabled public String targetDate;
        @AuraEnabled public Decimal requiredMonthlyContribution;
        @AuraEnabled public Decimal progressPercent;
        @AuraEnabled public Boolean onTrack;
    }

    public class DisputeRecord {
        @AuraEnabled public String disputeId;
        @AuraEnabled public String transactionId;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public List<String> statusSteps;
        @AuraEnabled public String createdAt;
        @AuraEnabled public String updatedAt;
    }

    public class LifeEvent {
        @AuraEnabled public String eventType;
        @AuraEnabled public String description;
        @AuraEnabled public String detectedDate;
    }

    public class LowBalanceAlert {
        @AuraEnabled public String paymentName;
        @AuraEnabled public String category;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal amountDue;
        @AuraEnabled public Decimal projectedBalanceBeforePayment;
        @AuraEnabled public Decimal projectedBalanceAfterPayment;
        @AuraEnabled public Boolean willFail;
        @AuraEnabled public Decimal shortfallAmount;
        @AuraEnabled public String recommendedAction;
    }

    public class LowBalanceWarningResult {
        @AuraEnabled public List<LowBalanceAlert> alerts;
        @AuraEnabled public String summary;
    }

    public class CategorySpendPrediction {
        @AuraEnabled public String category;
        @AuraEnabled public Decimal predictedAmount;
        @AuraEnabled public Decimal lastMonthAmount;
        @AuraEnabled public String trend;
        @AuraEnabled public Integer monthsOfHistory;
    }

    public class SpendPredictionResult {
        @AuraEnabled public List<CategorySpendPrediction> categories;
        @AuraEnabled public Decimal totalPredicted;
        @AuraEnabled public String explanation;
    }

    public class CategorySuggestion {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String description;
        @AuraEnabled public String currentCategory;
        @AuraEnabled public String suggestedCategory;
        @AuraEnabled public String matchedKeyword;
    }

    public class AutoCategorizationResult {
        @AuraEnabled public List<CategorySuggestion> suggestions;
        @AuraEnabled public String explanation;
    }

    @AuraEnabled
    public static LoanAffordabilityResult checkLoanAffordability(
        String bankAccountId, Decimal loanAmount, Integer tenureYears, Decimal annualRatePercent
    ) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{
                'loanAmount' => loanAmount,
                'tenureYears' => tenureYears,
                'annualRatePercent' => annualRatePercent
            };
            Object response = JavaBankingApiClient.post(
                accountPath(bankAccountId) + '/loan-affordability', contactId, JSON.serialize(body));
            return parseLoanResult((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static IdleFundsInsight getIdleFunds(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/idle-funds', contactId);
            return parseIdleFunds((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static ForecastResult getForecast(String bankAccountId, Integer days) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            String query = JavaBankingApiClient.buildQueryString(new Map<String, Object>{ 'days' => days });
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/forecast' + query, contactId);
            return parseForecast((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<SavingsGoal> getGoals(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/goals', contactId);
            return parseGoalList((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static SavingsGoal createGoal(String bankAccountId, String name, Decimal targetAmount, String targetDate) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{
                'name' => name,
                'targetAmount' => targetAmount,
                'targetDate' => targetDate
            };
            Object response = JavaBankingApiClient.post(
                accountPath(bankAccountId) + '/goals', contactId, JSON.serialize(body));
            return parseGoal((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static SavingsGoal addGoalContribution(String bankAccountId, String goalId, Decimal amount) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{ 'amount' => amount };
            Object response = JavaBankingApiClient.post(
                accountPath(bankAccountId) + '/goals/' + EncodingUtil.urlEncode(goalId, 'UTF-8') + '/contributions',
                contactId, JSON.serialize(body));
            return parseGoal((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<DisputeRecord> getDisputes(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/disputes', contactId);
            return parseDisputeList((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static DisputeRecord fileDispute(String bankAccountId, String transactionId, String description) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{
                'transactionId' => transactionId,
                'description' => description
            };
            Object response = JavaBankingApiClient.post(
                accountPath(bankAccountId) + '/disputes', contactId, JSON.serialize(body));
            return parseDispute((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<LifeEvent> getLifeEvents(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/life-events', contactId);
            return parseLifeEvents((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static LowBalanceWarningResult getLowBalanceWarnings(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/low-balance-warnings', contactId);
            return parseLowBalanceWarningResult((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static SpendPredictionResult getSpendPrediction(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/spend-prediction', contactId);
            return parseSpendPrediction((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static AutoCategorizationResult getCategorySuggestions(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/category-suggestions', contactId);
            return parseAutoCategorizationResult((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static CategorySuggestion applyCategorySuggestion(String bankAccountId, String transactionId, String newCategory) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{
                'transactionId' => transactionId,
                'newCategory' => newCategory
            };
            Object response = JavaBankingApiClient.post(
                accountPath(bankAccountId) + '/category-suggestions/apply', contactId, JSON.serialize(body));
            return parseCategorySuggestion((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    private static String accountPath(String bankAccountId) {
        return '/api/v1/accounts/' + EncodingUtil.urlEncode(bankAccountId, 'UTF-8');
    }

    private static AuraHandledException wrapAsAuraException(Exception e) {
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }

    @TestVisible
    private static LoanAffordabilityResult parseLoanResult(Map<String, Object> row) {
        LoanAffordabilityResult result = new LoanAffordabilityResult();
        result.estimatedMonthlyIncome = asDecimal(row.get('estimatedMonthlyIncome'));
        result.averageMonthlySpend = asDecimal(row.get('averageMonthlySpend'));
        result.requestedEmi = asDecimal(row.get('requestedEmi'));
        result.remainingAfterRequestedEmi = asDecimal(row.get('remainingAfterRequestedEmi'));
        result.emiBurdenPercentOfIncome = asDecimal(row.get('emiBurdenPercentOfIncome'));
        result.withinRecommendedBurden = (Boolean) row.get('withinRecommendedBurden');
        result.recommendedSaferLoanAmount = asDecimal(row.get('recommendedSaferLoanAmount'));
        result.recommendedSaferEmi = asDecimal(row.get('recommendedSaferEmi'));
        result.explanation = (String) row.get('explanation');
        return result;
    }

    @TestVisible
    private static IdleFundsInsight parseIdleFunds(Map<String, Object> row) {
        IdleFundsInsight insight = new IdleFundsInsight();
        insight.idle = (Boolean) row.get('idle');
        insight.currentBalance = asDecimal(row.get('currentBalance'));
        insight.averageMonthlySpend = asDecimal(row.get('averageMonthlySpend'));
        insight.recommendedFdAmount = asDecimal(row.get('recommendedFdAmount'));
        insight.estimatedAnnualGain = asDecimal(row.get('estimatedAnnualGain'));
        insight.explanation = (String) row.get('explanation');
        return insight;
    }

    @TestVisible
    private static ForecastResult parseForecast(Map<String, Object> row) {
        ForecastResult result = new ForecastResult();
        result.points = new List<ForecastPoint>();
        for (Object item : (List<Object>) row.get('points')) {
            Map<String, Object> pointRow = (Map<String, Object>) item;
            ForecastPoint point = new ForecastPoint();
            point.forecastDate = (String) pointRow.get('date');
            point.projectedBalance = asDecimal(pointRow.get('projectedBalance'));
            result.points.add(point);
        }
        result.safetyFloor = asDecimal(row.get('safetyFloor'));
        result.firstBreachDate = (String) row.get('firstBreachDate');
        result.explanation = (String) row.get('explanation');
        return result;
    }

    @TestVisible
    private static SavingsGoal parseGoal(Map<String, Object> row) {
        SavingsGoal goal = new SavingsGoal();
        goal.goalId = (String) row.get('id');
        goal.name = (String) row.get('name');
        goal.targetAmount = asDecimal(row.get('targetAmount'));
        goal.savedAmount = asDecimal(row.get('savedAmount'));
        goal.targetDate = (String) row.get('targetDate');
        goal.requiredMonthlyContribution = asDecimal(row.get('requiredMonthlyContribution'));
        goal.progressPercent = asDecimal(row.get('progressPercent'));
        goal.onTrack = (Boolean) row.get('onTrack');
        return goal;
    }

    @TestVisible
    private static List<SavingsGoal> parseGoalList(List<Object> raw) {
        List<SavingsGoal> goals = new List<SavingsGoal>();
        for (Object item : raw) {
            goals.add(parseGoal((Map<String, Object>) item));
        }
        return goals;
    }

    @TestVisible
    private static DisputeRecord parseDispute(Map<String, Object> row) {
        DisputeRecord dispute = new DisputeRecord();
        dispute.disputeId = (String) row.get('id');
        dispute.transactionId = (String) row.get('transactionId');
        dispute.description = (String) row.get('description');
        dispute.status = (String) row.get('status');
        dispute.statusSteps = new List<String>();
        for (Object step : (List<Object>) row.get('statusSteps')) {
            dispute.statusSteps.add((String) step);
        }
        dispute.createdAt = (String) row.get('createdAt');
        dispute.updatedAt = (String) row.get('updatedAt');
        return dispute;
    }

    @TestVisible
    private static List<DisputeRecord> parseDisputeList(List<Object> raw) {
        List<DisputeRecord> disputes = new List<DisputeRecord>();
        for (Object item : raw) {
            disputes.add(parseDispute((Map<String, Object>) item));
        }
        return disputes;
    }

    @TestVisible
    private static List<LifeEvent> parseLifeEvents(List<Object> raw) {
        List<LifeEvent> events = new List<LifeEvent>();
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            LifeEvent lifeEvent = new LifeEvent();
            lifeEvent.eventType = (String) row.get('type');
            lifeEvent.description = (String) row.get('description');
            lifeEvent.detectedDate = (String) row.get('detectedDate');
            events.add(lifeEvent);
        }
        return events;
    }

    @TestVisible
    private static LowBalanceAlert parseLowBalanceAlert(Map<String, Object> row) {
        LowBalanceAlert alert = new LowBalanceAlert();
        alert.paymentName = (String) row.get('paymentName');
        alert.category = (String) row.get('category');
        alert.dueDate = (String) row.get('dueDate');
        alert.amountDue = asDecimal(row.get('amountDue'));
        alert.projectedBalanceBeforePayment = asDecimal(row.get('projectedBalanceBeforePayment'));
        alert.projectedBalanceAfterPayment = asDecimal(row.get('projectedBalanceAfterPayment'));
        alert.willFail = (Boolean) row.get('willFail');
        alert.shortfallAmount = asDecimal(row.get('shortfallAmount'));
        alert.recommendedAction = (String) row.get('recommendedAction');
        return alert;
    }

    @TestVisible
    private static LowBalanceWarningResult parseLowBalanceWarningResult(Map<String, Object> row) {
        LowBalanceWarningResult result = new LowBalanceWarningResult();
        result.alerts = new List<LowBalanceAlert>();
        for (Object item : (List<Object>) row.get('alerts')) {
            result.alerts.add(parseLowBalanceAlert((Map<String, Object>) item));
        }
        result.summary = (String) row.get('summary');
        return result;
    }

    @TestVisible
    private static CategorySpendPrediction parseCategorySpendPrediction(Map<String, Object> row) {
        CategorySpendPrediction prediction = new CategorySpendPrediction();
        prediction.category = (String) row.get('category');
        prediction.predictedAmount = asDecimal(row.get('predictedAmount'));
        prediction.lastMonthAmount = asDecimal(row.get('lastMonthAmount'));
        prediction.trend = (String) row.get('trend');
        prediction.monthsOfHistory = row.get('monthsOfHistory') == null ? null : Integer.valueOf(String.valueOf(row.get('monthsOfHistory')));
        return prediction;
    }

    @TestVisible
    private static SpendPredictionResult parseSpendPrediction(Map<String, Object> row) {
        SpendPredictionResult result = new SpendPredictionResult();
        result.categories = new List<CategorySpendPrediction>();
        for (Object item : (List<Object>) row.get('categories')) {
            result.categories.add(parseCategorySpendPrediction((Map<String, Object>) item));
        }
        result.totalPredicted = asDecimal(row.get('totalPredicted'));
        result.explanation = (String) row.get('explanation');
        return result;
    }

    @TestVisible
    private static CategorySuggestion parseCategorySuggestion(Map<String, Object> row) {
        CategorySuggestion suggestion = new CategorySuggestion();
        suggestion.transactionId = (String) row.get('transactionId');
        suggestion.description = (String) row.get('description');
        suggestion.currentCategory = (String) row.get('currentCategory');
        suggestion.suggestedCategory = (String) row.get('suggestedCategory');
        suggestion.matchedKeyword = (String) row.get('matchedKeyword');
        return suggestion;
    }

    @TestVisible
    private static AutoCategorizationResult parseAutoCategorizationResult(Map<String, Object> row) {
        AutoCategorizationResult result = new AutoCategorizationResult();
        result.suggestions = new List<CategorySuggestion>();
        for (Object item : (List<Object>) row.get('suggestions')) {
            result.suggestions.add(parseCategorySuggestion((Map<String, Object>) item));
        }
        result.explanation = (String) row.get('explanation');
        return result;
    }

    private static Decimal asDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }
}