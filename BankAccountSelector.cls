public with sharing class BankAccountSelector {

    public class NoLinkedContactException extends Exception {}

    /**
     * The only Salesforce-specific concern the Apex layer still owns: mapping
     * the running user to the Contact Id used as the customer identifier by
     * the Java service. All ownership/authorization logic lives in Java.
     */
    public static Id resolveCurrentContactId() {
        Id contactId = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ].ContactId;

        if (contactId == null) {
            throw new NoLinkedContactException(
                'The current user is not linked to a Contact record.'
            );
        }
        return contactId;
    }
}