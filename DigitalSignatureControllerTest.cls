@IsTest
private class DigitalSignatureControllerTest {
    static Map<String, Object> seedDraft() {
        Map<String, Object> created = DigitalSignatureController.createRequest(
            'Home loan sanction',
            'Loan',
            'BR001',
            String.valueOf(System.now().addDays(2))
        );
        Id requestId = (Id) created.get('requestId');
        DigitalSignatureController.addDocument(
            requestId,
            'sanction.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('SANCTION LETTER BODY'))
        );
        DigitalSignatureController.addSigner(
            requestId,
            'Harini Dhayalan',
            'harini@example.com',
            '9999999999',
            'Applicant',
            1
        );
        return DigitalSignatureController.sendRequest(requestId);
    }

    static String signerAccessCode(Map<String, Object> payload) {
        List<Object> signers = (List<Object>) payload.get('signers');
        Map<String, Object> signer = (Map<String, Object>) signers[0];
        return (String) signer.get('Access_Code__c');
    }

    static Id signerId(Map<String, Object> payload) {
        List<Object> signers = (List<Object>) payload.get('signers');
        Map<String, Object> signer = (Map<String, Object>) signers[0];
        return (Id) signer.get('Id');
    }

    @IsTest
    static void sendOtpSignCompletes() {
        Test.startTest();
        Map<String, Object> sent = seedDraft();
        Id requestId = (Id) sent.get('requestId');
        Map<String, Object> otpResult = DigitalSignatureController.revealOtp(signerId(sent));
        String otp = (String) otpResult.get('otp');
        System.assertEquals(6, otp.length());
        Map<String, Object> signed = DigitalSignatureController.sign(
            signerAccessCode(sent),
            otp,
            'Typed',
            'HARINI DHAYALAN',
            true
        );
        Test.stopTest();
        Map<String, Object> request = (Map<String, Object>) signed.get('request');
        System.assertEquals('Completed', request.get('Status__c'));
        System.assertNotEquals(null, signed.get('signatureHash'));
        List<Signature_Event__c> events = [
            SELECT Event_Type__c FROM Signature_Event__c WHERE Request__c = :requestId ORDER BY CreatedDate
        ];
        System.assert(events.size() >= 4);
    }

    @IsTest
    static void wrongOtpFails() {
        Map<String, Object> sent = seedDraft();
        DigitalSignatureController.revealOtp(signerId(sent));
        Test.startTest();
        try {
            DigitalSignatureController.sign(
                signerAccessCode(sent),
                '000000',
                'Typed',
                'NAME',
                true
            );
            System.assert(false, 'Wrong OTP should fail');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('incorrect') || e.getMessage().contains('OTP'));
        }
        Test.stopTest();
    }

    @IsTest
    static void expiredRequestCannotSign() {
        Map<String, Object> created = DigitalSignatureController.createRequest(
            'Expired pack',
            'Mandate',
            'BR002',
            String.valueOf(System.now().addSeconds(-30))
        );
        Id requestId = (Id) created.get('requestId');
        DigitalSignatureController.addDocument(
            requestId,
            'mandate.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('MANDATE'))
        );
        DigitalSignatureController.addSigner(requestId, 'Officer One', 'a@b.com', '8888888888', 'Bank Officer', 1);
        Map<String, Object> sent = DigitalSignatureController.sendRequest(requestId);
        Test.startTest();
        Map<String, Object> loaded = DigitalSignatureController.loadRequest(requestId);
        Map<String, Object> request = (Map<String, Object>) loaded.get('request');
        System.assertEquals('Expired', request.get('Status__c'));
        try {
            DigitalSignatureController.revealOtp(signerId(sent));
            System.assert(false, 'Expired request should not issue OTP');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().toLowerCase().contains('expir'));
        }
        Test.stopTest();
    }

    @IsTest
    static void declineStopsRequest() {
        Map<String, Object> sent = seedDraft();
        Map<String, Object> otpResult = DigitalSignatureController.revealOtp(signerId(sent));
        Test.startTest();
        Map<String, Object> declined = DigitalSignatureController.decline(
            signerAccessCode(sent),
            (String) otpResult.get('otp'),
            'Customer refused'
        );
        Test.stopTest();
        Map<String, Object> request = (Map<String, Object>) declined.get('request');
        System.assertEquals('Declined', request.get('Status__c'));
    }

    @IsTest
    static void queueReturnsCreatedRequest() {
        seedDraft();
        Test.startTest();
        List<Map<String, Object>> queue = DigitalSignatureController.loadQueue();
        Test.stopTest();
        System.assert(!queue.isEmpty());
    }

    @IsTest
    static void saveDraftAndLoadForSigner() {
        Map<String, Object> sent = seedDraft();
        Id requestId = (Id) sent.get('requestId');
        Test.startTest();
        Map<String, Object> loaded = DigitalSignatureController.loadRequest(requestId);
        Map<String, Object> request = (Map<String, Object>) loaded.get('request');
        System.assertEquals('Sent', request.get('Status__c'));
        Map<String, Object> forSigner = DigitalSignatureController.loadForSigner(signerAccessCode(sent));
        Map<String, Object> signer = (Map<String, Object>) forSigner.get('signer');
        System.assertEquals('Viewed', signer.get('Status__c'));
        Test.stopTest();
        Signature_Request__c draft = new Signature_Request__c(
            Title__c = 'Draft only',
            Product_Type__c = 'Account',
            Status__c = 'Draft'
        );
        insert draft;
        Map<String, Object> saved = DigitalSignatureController.saveDraft(
            draft.Id,
            'Updated account pack',
            'Account',
            'BR009',
            String.valueOf(System.now().addDays(5))
        );
        Map<String, Object> savedReq = (Map<String, Object>) saved.get('request');
        System.assertEquals('Updated account pack', savedReq.get('Title__c'));
        try {
            DigitalSignatureController.createRequest('  ', 'Loan', 'BR001', String.valueOf(System.now().addDays(1)));
            System.assert(false, 'Blank title should fail');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }
}