public with sharing class StatementPdfController {

    public class UnauthorizedAccountException extends Exception {}

    public class TransactionLine {
        public String referenceNumber { get; set; }
        public String transactionDate { get; set; }
        public String description { get; set; }
        public String recordType { get; set; }
        public Decimal amount { get; set; }
        public Decimal runningBalance { get; set; }
        public String status { get; set; }
    }

    public String accountNumber { get; private set; }
    public String accountType { get; private set; }
    public Decimal balance { get; private set; }
    public List<TransactionLine> transactions { get; private set; }
    public Date startDate { get; private set; }
    public Date endDate { get; private set; }

    public StatementPdfController() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        String bankAccountId = params.get('accountId');
        startDate = params.containsKey('startDate') && String.isNotBlank(params.get('startDate'))
            ? Date.valueOf(params.get('startDate'))
            : Date.today().toStartOfMonth();
        endDate = params.containsKey('endDate') && String.isNotBlank(params.get('endDate'))
            ? Date.valueOf(params.get('endDate'))
            : Date.today();

        Id contactId = BankAccountSelector.resolveCurrentContactId();

        Map<String, Object> ownedAccount = findOwnedAccount(contactId, bankAccountId);
        if (ownedAccount == null) {
            throw new UnauthorizedAccountException('This account does not belong to the current user.');
        }
        accountNumber = (String) ownedAccount.get('accountNumber');
        accountType = (String) ownedAccount.get('accountType');
        balance = asDecimal(ownedAccount.get('balance'));

        transactions = loadTransactions(contactId, bankAccountId);
    }

    private Map<String, Object> findOwnedAccount(Id contactId, String bankAccountId) {
        List<Object> accounts = (List<Object>) JavaBankingApiClient.get('/api/v1/accounts', contactId);
        for (Object item : accounts) {
            Map<String, Object> acc = (Map<String, Object>) item;
            if (bankAccountId == String.valueOf(acc.get('accountId'))) {
                return acc;
            }
        }
        return null;
    }

    private List<TransactionLine> loadTransactions(Id contactId, String bankAccountId) {
        String query = JavaBankingApiClient.buildQueryString(new Map<String, Object>{
            'startDate' => startDate,
            'endDate' => endDate
        });
        List<Object> rawTransactions = (List<Object>) JavaBankingApiClient.get(
            '/api/v1/accounts/' + EncodingUtil.urlEncode(bankAccountId, 'UTF-8') + '/transactions/export' + query,
            contactId
        );

        List<TransactionLine> lines = new List<TransactionLine>();
        for (Object item : rawTransactions) {
            Map<String, Object> row = (Map<String, Object>) item;
            TransactionLine line = new TransactionLine();
            line.referenceNumber = (String) row.get('referenceNumber');
            line.transactionDate = (String) row.get('transactionDate');
            line.description = (String) row.get('description');
            line.recordType = (String) row.get('recordType');
            line.amount = asDecimal(row.get('amount'));
            line.runningBalance = asDecimal(row.get('runningBalance'));
            line.status = (String) row.get('status');
            lines.add(line);
        }
        return lines;
    }

    private static Decimal asDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }
}