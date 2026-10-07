/**
 * Thin proxy to the Java banking API. No SOQL, no business logic, no
 * ownership checks - the Java service enforces all of that. This class only
 * resolves the caller's identity, forwards the call, and reshapes the JSON
 * response into the same wire format the LWCs already expect.
 */
public with sharing class AccountStatementController {

    public class BankAccountOption {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String accountType;
        @AuraEnabled public Decimal balance;
        @AuraEnabled public Boolean isPrimary;
    }

    public class StatementOverview {
        @AuraEnabled public Decimal currentBalance;
        @AuraEnabled public Decimal availableBalance;
        @AuraEnabled public Decimal balanceDeltaPercent;
        @AuraEnabled public Decimal totalCredits;
        @AuraEnabled public Integer creditCount;
        @AuraEnabled public Decimal totalDebits;
        @AuraEnabled public Integer debitCount;
        @AuraEnabled public Decimal totalFees;
        @AuraEnabled public Integer feeCount;
        @AuraEnabled public Decimal closingBalance;
        @AuraEnabled public Decimal closingBalanceDeltaPercent;
    }

    public class CashflowPoint {
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Decimal credit;
        @AuraEnabled public Decimal debit;
    }

    public class TransactionRow {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String transactionDate;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public String recordType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal runningBalance;
        @AuraEnabled public String status;
    }

    public class TransactionPage {
        @AuraEnabled public List<TransactionRow> rows;
        @AuraEnabled public Integer totalCount;
    }

    public class FraudFlag {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String transactionDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String reason;
        @AuraEnabled public String severity;
    }

    public class DashboardMetrics {
        @AuraEnabled public Decimal totalDeposits;
        @AuraEnabled public Decimal totalDepositsTrendPercent;
        @AuraEnabled public Decimal monthlyIncome;
        @AuraEnabled public Decimal monthlyIncomeTrendPercent;
        @AuraEnabled public Decimal monthlySpending;
        @AuraEnabled public Decimal monthlySpendingTrendPercent;
        @AuraEnabled public Integer rewardsPoints;
        @AuraEnabled public Integer rewardsPointsDelta;
    }

    public class DashboardTrendPoint {
        @AuraEnabled public String monthLabel;
        @AuraEnabled public Decimal balance;
    }

    public class DashboardSpendCategory {
        @AuraEnabled public String category;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Integer percent;
    }

    public class DashboardPayment {
        @AuraEnabled public String paymentId;
        @AuraEnabled public String name;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String category;
    }

    public class DashboardTransaction {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String transactionDate;
        @AuraEnabled public String description;
        @AuraEnabled public String category;
        @AuraEnabled public String recordType;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String status;
    }

    public class DashboardCard {
        @AuraEnabled public String cardId;
        @AuraEnabled public String kind;
        @AuraEnabled public String lastFour;
        @AuraEnabled public String status;
    }

    public class DashboardInvestment {
        @AuraEnabled public String investmentId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
    }

    public class DashboardGoal {
        @AuraEnabled public String goalId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal savedAmount;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Decimal progressPercent;
    }

    public class DashboardLoan {
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal emiAmount;
        @AuraEnabled public String nextDueDate;
        @AuraEnabled public String status;
    }

    public class DashboardSnapshot {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String lastFour;
        @AuraEnabled public String accountType;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public String productTier;
        @AuraEnabled public String ifsc;
        @AuraEnabled public String branchName;
        @AuraEnabled public String openedOn;
        @AuraEnabled public Boolean kycVerified;
        @AuraEnabled public Decimal currentBalance;
        @AuraEnabled public Decimal availableBalance;
        @AuraEnabled public Decimal balanceDeltaPercent;
        @AuraEnabled public Decimal monthChange;
        @AuraEnabled public Decimal pendingHolds;
        @AuraEnabled public Decimal lastCredit;
        @AuraEnabled public Decimal todaySpend;
        @AuraEnabled public DashboardMetrics metrics;
        @AuraEnabled public List<DashboardTrendPoint> trend;
        @AuraEnabled public List<DashboardSpendCategory> spendCategories;
        @AuraEnabled public List<DashboardPayment> upcomingPayments;
        @AuraEnabled public List<DashboardTransaction> recentTransactions;
        @AuraEnabled public List<DashboardCard> cards;
        @AuraEnabled public List<DashboardInvestment> investments;
        @AuraEnabled public List<DashboardGoal> goals;
        @AuraEnabled public List<String> insights;
        @AuraEnabled public DashboardLoan loan;
    }

    @AuraEnabled
    public static List<BankAccountOption> getMyAccounts() {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get('/api/v1/accounts', contactId);
            return parseAccountList((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static StatementOverview getStatementOverview(String bankAccountId, Date startDate, Date endDate) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            String query = JavaBankingApiClient.buildQueryString(new Map<String, Object>{
                'startDate' => startDate,
                'endDate' => endDate
            });
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/statement-overview' + query, contactId);
            return parseOverview((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<CashflowPoint> getMonthlyCashflow(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/monthly-cashflow', contactId);
            return parseCashflow((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static TransactionPage getTransactions(
        String bankAccountId,
        Date startDate,
        Date endDate,
        String txnType,
        String searchTerm,
        Integer pageNumber,
        Integer pageSize
    ) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            String query = JavaBankingApiClient.buildQueryString(new Map<String, Object>{
                'startDate' => startDate,
                'endDate' => endDate,
                'txnType' => txnType,
                'searchTerm' => searchTerm,
                'pageNumber' => pageNumber,
                'pageSize' => pageSize
            });
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/transactions' + query, contactId);
            return parseTransactionPage((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<TransactionRow> getTransactionsForExport(
        String bankAccountId,
        Date startDate,
        Date endDate,
        String txnType,
        String searchTerm
    ) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            String query = JavaBankingApiClient.buildQueryString(new Map<String, Object>{
                'startDate' => startDate,
                'endDate' => endDate,
                'txnType' => txnType,
                'searchTerm' => searchTerm
            });
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/transactions/export' + query, contactId);
            return parseTransactionRowList((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<String> getInsights(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/insights', contactId);
            List<String> insights = new List<String>();
            for (Object item : (List<Object>) response) {
                insights.add((String) item);
            }
            return insights;
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static DashboardSnapshot getDashboard(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/dashboard', contactId);
            return parseDashboard((Map<String, Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @AuraEnabled
    public static List<FraudFlag> getFraudFlags(String bankAccountId) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Object response = JavaBankingApiClient.get(accountPath(bankAccountId) + '/fraud-flags', contactId);
            return parseFraudFlags((List<Object>) response);
        } catch (Exception e) {
            throw wrapAsAuraException(e);
        }
    }

    @TestVisible
    private static List<FraudFlag> parseFraudFlags(List<Object> raw) {
        List<FraudFlag> flags = new List<FraudFlag>();
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            FraudFlag flag = new FraudFlag();
            flag.transactionId = (String) row.get('transactionId');
            flag.transactionDate = (String) row.get('transactionDate');
            flag.amount = asDecimal(row.get('amount'));
            flag.reason = (String) row.get('reason');
            flag.severity = (String) row.get('severity');
            flags.add(flag);
        }
        return flags;
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
    private static List<BankAccountOption> parseAccountList(List<Object> raw) {
        List<BankAccountOption> options = new List<BankAccountOption>();
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            BankAccountOption opt = new BankAccountOption();
            opt.accountId = (String) row.get('accountId');
            opt.accountNumber = (String) row.get('accountNumber');
            opt.accountType = (String) row.get('accountType');
            opt.balance = asDecimal(row.get('balance'));
            opt.isPrimary = (Boolean) row.get('isPrimary');
            options.add(opt);
        }
        return options;
    }

    @TestVisible
    private static StatementOverview parseOverview(Map<String, Object> row) {
        StatementOverview overview = new StatementOverview();
        overview.currentBalance = asDecimal(row.get('currentBalance'));
        overview.availableBalance = asDecimal(row.get('availableBalance'));
        overview.balanceDeltaPercent = asDecimal(row.get('balanceDeltaPercent'));
        overview.totalCredits = asDecimal(row.get('totalCredits'));
        overview.creditCount = asInteger(row.get('creditCount'));
        overview.totalDebits = asDecimal(row.get('totalDebits'));
        overview.debitCount = asInteger(row.get('debitCount'));
        overview.totalFees = asDecimal(row.get('totalFees'));
        overview.feeCount = asInteger(row.get('feeCount'));
        overview.closingBalance = asDecimal(row.get('closingBalance'));
        overview.closingBalanceDeltaPercent = asDecimal(row.get('closingBalanceDeltaPercent'));
        return overview;
    }

    @TestVisible
    private static List<CashflowPoint> parseCashflow(List<Object> raw) {
        List<CashflowPoint> points = new List<CashflowPoint>();
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            CashflowPoint point = new CashflowPoint();
            point.monthLabel = (String) row.get('monthLabel');
            point.credit = asDecimal(row.get('credit'));
            point.debit = asDecimal(row.get('debit'));
            points.add(point);
        }
        return points;
    }

    @TestVisible
    private static TransactionRow parseTransactionRow(Map<String, Object> row) {
        TransactionRow txn = new TransactionRow();
        txn.transactionId = (String) row.get('transactionId');
        txn.referenceNumber = (String) row.get('referenceNumber');
        txn.transactionDate = (String) row.get('transactionDate');
        txn.description = (String) row.get('description');
        txn.category = (String) row.get('category');
        txn.recordType = (String) row.get('recordType');
        txn.amount = asDecimal(row.get('amount'));
        txn.runningBalance = asDecimal(row.get('runningBalance'));
        txn.status = (String) row.get('status');
        return txn;
    }

    @TestVisible
    private static TransactionPage parseTransactionPage(Map<String, Object> raw) {
        TransactionPage page = new TransactionPage();
        page.rows = parseTransactionRowList((List<Object>) raw.get('rows'));
        page.totalCount = asInteger(raw.get('totalCount'));
        return page;
    }

    @TestVisible
    private static List<TransactionRow> parseTransactionRowList(List<Object> raw) {
        List<TransactionRow> rows = new List<TransactionRow>();
        for (Object item : raw) {
            rows.add(parseTransactionRow((Map<String, Object>) item));
        }
        return rows;
    }

    @TestVisible
    private static DashboardSnapshot parseDashboard(Map<String, Object> row) {
        DashboardSnapshot snap = new DashboardSnapshot();
        snap.accountId = (String) row.get('accountId');
        snap.accountNumber = (String) row.get('accountNumber');
        snap.lastFour = (String) row.get('lastFour');
        snap.accountType = (String) row.get('accountType');
        snap.isPrimary = (Boolean) row.get('isPrimary');
        if (snap.isPrimary == null) {
            snap.isPrimary = (Boolean) row.get('primary');
        }
        snap.productTier = (String) row.get('productTier');
        snap.ifsc = (String) row.get('ifsc');
        snap.branchName = (String) row.get('branchName');
        snap.openedOn = (String) row.get('openedOn');
        snap.kycVerified = (Boolean) row.get('kycVerified');
        snap.currentBalance = asDecimal(row.get('currentBalance'));
        snap.availableBalance = asDecimal(row.get('availableBalance'));
        snap.balanceDeltaPercent = asDecimal(row.get('balanceDeltaPercent'));
        snap.monthChange = asDecimal(row.get('monthChange'));
        snap.pendingHolds = asDecimal(row.get('pendingHolds'));
        snap.lastCredit = asDecimal(row.get('lastCredit'));
        snap.todaySpend = asDecimal(row.get('todaySpend'));
        snap.metrics = parseDashboardMetrics((Map<String, Object>) row.get('metrics'));
        snap.trend = parseDashboardTrend((List<Object>) row.get('trend'));
        snap.spendCategories = parseDashboardSpend((List<Object>) row.get('spendCategories'));
        snap.upcomingPayments = parseDashboardPayments((List<Object>) row.get('upcomingPayments'));
        snap.recentTransactions = parseDashboardTransactions((List<Object>) row.get('recentTransactions'));
        snap.cards = parseDashboardCards((List<Object>) row.get('cards'));
        snap.investments = parseDashboardInvestments((List<Object>) row.get('investments'));
        snap.goals = parseDashboardGoals((List<Object>) row.get('goals'));
        snap.insights = new List<String>();
        if (row.get('insights') != null) {
            for (Object item : (List<Object>) row.get('insights')) {
                snap.insights.add((String) item);
            }
        }
        if (row.get('loan') != null) {
            Map<String, Object> loanRow = (Map<String, Object>) row.get('loan');
            DashboardLoan loan = new DashboardLoan();
            loan.productName = (String) loanRow.get('productName');
            loan.emiAmount = asDecimal(loanRow.get('emiAmount'));
            loan.nextDueDate = (String) loanRow.get('nextDueDate');
            loan.status = (String) loanRow.get('status');
            snap.loan = loan;
        }
        return snap;
    }

    private static DashboardMetrics parseDashboardMetrics(Map<String, Object> row) {
        DashboardMetrics metrics = new DashboardMetrics();
        if (row == null) {
            return metrics;
        }
        metrics.totalDeposits = asDecimal(row.get('totalDeposits'));
        metrics.totalDepositsTrendPercent = asDecimal(row.get('totalDepositsTrendPercent'));
        metrics.monthlyIncome = asDecimal(row.get('monthlyIncome'));
        metrics.monthlyIncomeTrendPercent = asDecimal(row.get('monthlyIncomeTrendPercent'));
        metrics.monthlySpending = asDecimal(row.get('monthlySpending'));
        metrics.monthlySpendingTrendPercent = asDecimal(row.get('monthlySpendingTrendPercent'));
        metrics.rewardsPoints = asInteger(row.get('rewardsPoints'));
        metrics.rewardsPointsDelta = asInteger(row.get('rewardsPointsDelta'));
        return metrics;
    }

    private static List<DashboardTrendPoint> parseDashboardTrend(List<Object> raw) {
        List<DashboardTrendPoint> points = new List<DashboardTrendPoint>();
        if (raw == null) {
            return points;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardTrendPoint point = new DashboardTrendPoint();
            point.monthLabel = (String) row.get('monthLabel');
            point.balance = asDecimal(row.get('balance'));
            points.add(point);
        }
        return points;
    }

    private static List<DashboardSpendCategory> parseDashboardSpend(List<Object> raw) {
        List<DashboardSpendCategory> categories = new List<DashboardSpendCategory>();
        if (raw == null) {
            return categories;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardSpendCategory category = new DashboardSpendCategory();
            category.category = (String) row.get('category');
            category.label = (String) row.get('label');
            category.amount = asDecimal(row.get('amount'));
            category.percent = asInteger(row.get('percent'));
            categories.add(category);
        }
        return categories;
    }

    private static List<DashboardPayment> parseDashboardPayments(List<Object> raw) {
        List<DashboardPayment> payments = new List<DashboardPayment>();
        if (raw == null) {
            return payments;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardPayment payment = new DashboardPayment();
            payment.paymentId = (String) row.get('paymentId');
            payment.name = (String) row.get('name');
            payment.dueDate = (String) row.get('dueDate');
            payment.amount = asDecimal(row.get('amount'));
            payment.category = (String) row.get('category');
            payments.add(payment);
        }
        return payments;
    }

    private static List<DashboardTransaction> parseDashboardTransactions(List<Object> raw) {
        List<DashboardTransaction> rows = new List<DashboardTransaction>();
        if (raw == null) {
            return rows;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardTransaction txn = new DashboardTransaction();
            txn.transactionId = (String) row.get('transactionId');
            txn.transactionDate = (String) row.get('transactionDate');
            txn.description = (String) row.get('description');
            txn.category = (String) row.get('category');
            txn.recordType = (String) row.get('recordType');
            txn.amount = asDecimal(row.get('amount'));
            txn.status = (String) row.get('status');
            rows.add(txn);
        }
        return rows;
    }

    private static List<DashboardCard> parseDashboardCards(List<Object> raw) {
        List<DashboardCard> cards = new List<DashboardCard>();
        if (raw == null) {
            return cards;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardCard card = new DashboardCard();
            card.cardId = (String) row.get('cardId');
            card.kind = (String) row.get('kind');
            card.lastFour = (String) row.get('lastFour');
            card.status = (String) row.get('status');
            cards.add(card);
        }
        return cards;
    }

    private static List<DashboardInvestment> parseDashboardInvestments(List<Object> raw) {
        List<DashboardInvestment> investments = new List<DashboardInvestment>();
        if (raw == null) {
            return investments;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardInvestment investment = new DashboardInvestment();
            investment.investmentId = (String) row.get('investmentId');
            investment.name = (String) row.get('name');
            investment.amount = asDecimal(row.get('amount'));
            investments.add(investment);
        }
        return investments;
    }

    private static List<DashboardGoal> parseDashboardGoals(List<Object> raw) {
        List<DashboardGoal> goals = new List<DashboardGoal>();
        if (raw == null) {
            return goals;
        }
        for (Object item : raw) {
            Map<String, Object> row = (Map<String, Object>) item;
            DashboardGoal goal = new DashboardGoal();
            goal.goalId = (String) row.get('goalId');
            goal.name = (String) row.get('name');
            goal.savedAmount = asDecimal(row.get('savedAmount'));
            goal.targetAmount = asDecimal(row.get('targetAmount'));
            goal.progressPercent = asDecimal(row.get('progressPercent'));
            goals.add(goal);
        }
        return goals;
    }

    private static Decimal asDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Integer asInteger(Object value) {
        return value == null ? null : Integer.valueOf(String.valueOf(value));
    }
}