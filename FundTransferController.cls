/**
 * Thin proxy to the Java banking API's transfer endpoint. Same pattern as
 * AccountStatementController - resolves identity, forwards the request,
 * reshapes the response. All validation (ownership, sufficient funds) is
 * enforced by Java.
 */
public with sharing class FundTransferController {

    public class TransferResult {
        @AuraEnabled public String transactionId;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public Decimal newBalance;
        @AuraEnabled public String status;
    }

    @AuraEnabled
    public static TransferResult transferFunds(
        String fromAccountId,
        String toAccountNumber,
        Decimal amount,
        String description
    ) {
        try {
            Id contactId = BankAccountSelector.resolveCurrentContactId();
            Map<String, Object> body = new Map<String, Object>{
                'toAccountNumber' => toAccountNumber,
                'amount' => amount,
                'description' => description
            };
            Object response = JavaBankingApiClient.post(
                '/api/v1/accounts/' + EncodingUtil.urlEncode(fromAccountId, 'UTF-8') + '/transfer',
                contactId,
                JSON.serialize(body)
            );
            return parseResult((Map<String, Object>) response);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    @TestVisible
    private static TransferResult parseResult(Map<String, Object> row) {
        TransferResult result = new TransferResult();
        result.transactionId = (String) row.get('transactionId');
        result.referenceNumber = (String) row.get('referenceNumber');
        result.newBalance = row.get('newBalance') == null ? null : Decimal.valueOf(String.valueOf(row.get('newBalance')));
        result.status = (String) row.get('status');
        return result;
    }
}