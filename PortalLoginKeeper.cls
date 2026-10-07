/**
 * Keeps EngageIQ Experience Cloud + admin login usable in this demo org:
 * re-applies demo passwords and clears lockouts.
 */
public without sharing class PortalLoginKeeper implements Schedulable {
    public static final List<String> PORTAL_USERNAMES = new List<String>{
        'john.smith.ibportal@levarus.com'
    };
    public static final List<String> ADMIN_USERNAMES = new List<String>{
        'seethalakshmi@levarus.com'
    };
    public static final List<String> UNLOCK_USERNAMES = new List<String>{
        'john.smith.ibportal@levarus.com',
        'seethalakshmi@levarus.com'
    };
    // Demo passwords (dev org only).
    private static final String PORTAL_PASSWORD = 'AJAY@234';
    private static final String ADMIN_PASSWORD = 'GARY@2708';
    private static final String TEMP_PASSWORD = 'TempPass1a!';
    private static final String TEMP_PASSWORD_B = 'TempPass2b!';

    public void execute(SchedulableContext sc) {
        keepLoginsWorking();
    }

    @AuraEnabled
    public static Integer unlockPortalUsers() {
        return keepLoginsWorking();
    }

    @AuraEnabled
    public static Integer keepLoginsWorking() {
        clearLocks();
        Integer resetCount = 0;
        resetCount += resetPasswords(PORTAL_USERNAMES, PORTAL_PASSWORD);
        resetCount += resetPasswords(ADMIN_USERNAMES, ADMIN_PASSWORD);
        clearLocks();
        return resetCount;
    }

    private static Integer resetPasswords(List<String> usernames, String password) {
        List<User> users = [
            SELECT Id, Username
            FROM User
            WHERE Username IN :usernames
            AND IsActive = true
        ];
        for (User u : users) {
            // Rotate so Salesforce history rules cannot block the target password.
            System.setPassword(u.Id, TEMP_PASSWORD);
            System.setPassword(u.Id, TEMP_PASSWORD_B);
            System.setPassword(u.Id, password);
        }
        return users.size();
    }

    private static void clearLocks() {
        List<UserLogin> locks = [
            SELECT Id, IsPasswordLocked
            FROM UserLogin
            WHERE UserId IN (
                SELECT Id FROM User WHERE Username IN :UNLOCK_USERNAMES
            )
            AND IsPasswordLocked = true
        ];
        for (UserLogin row : locks) {
            row.IsPasswordLocked = false;
        }
        if (!locks.isEmpty()) {
            update locks;
        }
    }

    public static String ensureSchedule() {
        for (CronTrigger ct : [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'PortalLoginKeeper%'
        ]) {
            System.abortJob(ct.Id);
        }
        List<Integer> mins = new List<Integer>{ 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55 };
        String firstId;
        for (Integer m : mins) {
            String cron = '0 ' + String.valueOf(m) + ' * * * ?';
            String id = System.schedule('PortalLoginKeeper m' + String.valueOf(m), cron, new PortalLoginKeeper());
            if (firstId == null) {
                firstId = id;
            }
        }
        unlockPortalUsers();
        return firstId;
    }
}
