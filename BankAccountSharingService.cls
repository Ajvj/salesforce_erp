public with sharing class BankAccountSharingService {

    public static void shareWithOwningCustomer(List<Bank_Account__c> accounts) {
        Map<Id, Id> contactIdToUserId = getActivePortalUserIdsByContact(accounts);
        if (contactIdToUserId.isEmpty()) {
            return;
        }

        List<Bank_Account__Share> shares = buildShares(accounts, contactIdToUserId);
        if (!shares.isEmpty()) {
            // allOrNone=false: a share row may already exist for this account/user
            // (e.g. an unrelated field update re-firing the trigger) which Salesforce
            // rejects as a duplicate - that failure should not block other records.
            Database.insert(shares, false);
        }
    }

    @TestVisible
    private static Map<Id, Id> getActivePortalUserIdsByContact(List<Bank_Account__c> accounts) {
        Set<Id> contactIds = new Set<Id>();
        for (Bank_Account__c acc : accounts) {
            if (acc.Contact__c != null) {
                contactIds.add(acc.Contact__c);
            }
        }

        Map<Id, Id> contactIdToUserId = new Map<Id, Id>();
        if (contactIds.isEmpty()) {
            return contactIdToUserId;
        }

        for (User u : [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
        ]) {
            contactIdToUserId.put(u.ContactId, u.Id);
        }
        return contactIdToUserId;
    }

    @TestVisible
    private static List<Bank_Account__Share> buildShares(
        List<Bank_Account__c> accounts,
        Map<Id, Id> contactIdToUserId
    ) {
        List<Bank_Account__Share> shares = new List<Bank_Account__Share>();
        for (Bank_Account__c acc : accounts) {
            Id userId = contactIdToUserId.get(acc.Contact__c);
            if (userId != null) {
                Bank_Account__Share share = new Bank_Account__Share();
                share.ParentId = acc.Id;
                share.UserOrGroupId = userId;
                share.AccessLevel = 'Read';
                share.RowCause = Schema.Bank_Account__Share.RowCause.Customer_Access__c;
                shares.add(share);
            }
        }
        return shares;
    }
}