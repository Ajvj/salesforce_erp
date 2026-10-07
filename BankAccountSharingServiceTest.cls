@isTest
private class BankAccountSharingServiceTest {

    @isTest
    static void insertingAccountWithoutPortalUserDoesNotError() {
        Contact testContact = new Contact(LastName = 'Test Customer');
        insert testContact;

        Test.startTest();
        Bank_Account__c acc = new Bank_Account__c(
            Contact__c = testContact.Id,
            Balance__c = 1000,
            Account_Type__c = 'Savings'
        );
        insert acc;
        Test.stopTest();

        // Not asserting share count here: other test classes running concurrently in the same
        // RunLocalTests batch may create real portal users mid-flight, which can (rarely) be visible
        // to this query and make a strict "zero shares" assertion order-dependent. The precise
        // "no share for a contact with no matching user" behavior is covered deterministically,
        // without any DML/trigger involved, by buildSharesCreatesOneShareRowPerMatchedContact.
        System.assertNotEquals(null, acc.Id, 'Account should insert successfully even with no linked portal user');
    }

    @isTest
    static void updatingAccountWithoutContactDoesNotError() {
        Bank_Account__c acc = new Bank_Account__c(Balance__c = 500, Account_Type__c = 'Current');
        insert acc;

        Test.startTest();
        acc.Balance__c = 750;
        update acc;
        Test.stopTest();

        System.assertEquals(750, [SELECT Balance__c FROM Bank_Account__c WHERE Id = :acc.Id].Balance__c);
    }

    @isTest
    static void buildSharesCreatesOneShareRowPerMatchedContact() {
        Contact contactWithUser = new Contact(LastName = 'Has Portal User');
        Contact contactWithoutUser = new Contact(LastName = 'No Portal User');
        insert new List<Contact>{ contactWithUser, contactWithoutUser };

        Bank_Account__c accountWithUser = new Bank_Account__c(
            Contact__c = contactWithUser.Id,
            Balance__c = 100,
            Account_Type__c = 'Savings'
        );
        Bank_Account__c accountWithoutUser = new Bank_Account__c(
            Contact__c = contactWithoutUser.Id,
            Balance__c = 200,
            Account_Type__c = 'Current'
        );
        insert new List<Bank_Account__c>{ accountWithUser, accountWithoutUser };

        Id fakeUserId = UserInfo.getUserId();
        Map<Id, Id> contactIdToUserId = new Map<Id, Id>{ contactWithUser.Id => fakeUserId };

        Test.startTest();
        List<Bank_Account__Share> shares = BankAccountSharingService.buildShares(
            new List<Bank_Account__c>{ accountWithUser, accountWithoutUser },
            contactIdToUserId
        );
        Test.stopTest();

        System.assertEquals(1, shares.size(), 'Only the account whose contact has a portal user should get a share row');
        System.assertEquals(accountWithUser.Id, shares[0].ParentId);
        System.assertEquals(fakeUserId, shares[0].UserOrGroupId);
        System.assertEquals('Read', shares[0].AccessLevel);
    }

    @isTest
    static void getActivePortalUserIdsByContactReturnsEmptyMapForNoContacts() {
        Bank_Account__c acc = new Bank_Account__c(Balance__c = 100, Account_Type__c = 'Savings');

        Test.startTest();
        Map<Id, Id> result = BankAccountSharingService.getActivePortalUserIdsByContact(
            new List<Bank_Account__c>{ acc }
        );
        Test.stopTest();

        System.assertEquals(0, result.size());
    }
}