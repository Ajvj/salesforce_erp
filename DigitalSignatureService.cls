public with sharing class DigitalSignatureService {
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_IN_PROGRESS = 'In Progress';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_DECLINED = 'Declined';
    public static final String STATUS_EXPIRED = 'Expired';

    public static String sha256Hex(String input) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(input == null ? '' : input));
        return EncodingUtil.convertToHex(digest);
    }

    public static String sha256Hex(Blob body) {
        Blob digest = Crypto.generateDigest('SHA-256', body == null ? Blob.valueOf('') : body);
        return EncodingUtil.convertToHex(digest);
    }

    public static String generateOtp() {
        Integer value = Math.mod(Math.abs(Crypto.getRandomInteger()), 1000000);
        return String.valueOf(value).leftPad(6, '0');
    }

    public static String generateAccessCode() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).toUpperCase().left(8);
    }

    public static String hashOtp(Id signerId, String otp) {
        return sha256Hex(String.valueOf(signerId) + ':' + (otp == null ? '' : otp.trim()));
    }

    public static void writeEvent(
        Id requestId,
        Id signerId,
        String eventType,
        String documentHash,
        String signatureHash,
        String notes
    ) {
        Database.insert(
            new Signature_Event__c(
                Request__c = requestId,
                Signer__c = signerId,
                Event_Type__c = eventType,
                Actor__c = UserInfo.getName(),
                Document_Hash__c = documentHash,
                Signature_Hash__c = signatureHash,
                Occurred_At__c = System.now(),
                Notes__c = notes
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    public static Signature_Request__c requireRequest(Id requestId) {
        List<Signature_Request__c> rows = [
            SELECT Id, Name, Title__c, Product_Type__c, Branch_Code__c, Status__c,
                   Expires_On__c, Sent_At__c, Completed_At__c, Document_Count__c,
                   Signer_Count__c, Signed_Count__c
            FROM Signature_Request__c
            WHERE Id = :requestId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Signature request was not found.');
        }
        return rows[0];
    }

    public static void refreshCounts(Id requestId) {
        Signature_Request__c request = new Signature_Request__c(
            Id = requestId,
            Document_Count__c = [
                SELECT COUNT() FROM Signature_Document__c WHERE Request__c = :requestId WITH SYSTEM_MODE
            ],
            Signer_Count__c = [
                SELECT COUNT() FROM Signature_Signer__c WHERE Request__c = :requestId WITH SYSTEM_MODE
            ],
            Signed_Count__c = [
                SELECT COUNT()
                FROM Signature_Signer__c
                WHERE Request__c = :requestId AND Status__c = 'Signed'
                WITH SYSTEM_MODE
            ]
        );
        Database.update(request, AccessLevel.SYSTEM_MODE);
    }

    public static String combinedDocumentHash(Id requestId) {
        List<String> hashes = new List<String>();
        for (Signature_Document__c doc : [
            SELECT Content_Hash__c
            FROM Signature_Document__c
            WHERE Request__c = :requestId
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c, CreatedDate
        ]) {
            hashes.add(String.isBlank(doc.Content_Hash__c) ? '' : doc.Content_Hash__c);
        }
        return sha256Hex(String.join(hashes, '|'));
    }

    public static Boolean isExpired(Signature_Request__c request) {
        return request.Expires_On__c != null &&
            request.Expires_On__c < System.now() &&
            request.Status__c != STATUS_COMPLETED &&
            request.Status__c != STATUS_DECLINED;
    }

    public static void markExpired(Signature_Request__c request) {
        request.Status__c = STATUS_EXPIRED;
        Database.update(request, AccessLevel.SYSTEM_MODE);
        List<Signature_Signer__c> signers = [
            SELECT Id, Status__c
            FROM Signature_Signer__c
            WHERE Request__c = :request.Id AND Status__c NOT IN ('Signed', 'Declined')
            WITH SYSTEM_MODE
        ];
        for (Signature_Signer__c signer : signers) {
            signer.Status__c = 'Expired';
        }
        if (!signers.isEmpty()) {
            Database.update(signers, AccessLevel.SYSTEM_MODE);
        }
        writeEvent(request.Id, null, 'Expired', combinedDocumentHash(request.Id), null, 'The request expired.');
    }

    public static Signature_Signer__c nextPendingSigner(Id requestId) {
        List<Signature_Signer__c> rows = [
            SELECT Id, Full_Name__c, Status__c, Signing_Order__c
            FROM Signature_Signer__c
            WHERE Request__c = :requestId AND Status__c IN ('Pending', 'OTP Sent', 'Viewed')
            WITH SYSTEM_MODE
            ORDER BY Signing_Order__c, CreatedDate
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}