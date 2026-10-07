@IsTest
private class RetailApplicationControllerTest {
    @IsTest
    static void createsSavesAndUploadsWithOcr() {
        Test.startTest();
        RetailApplicationController.Draft draft = RetailApplicationController.getOrCreateDraft();
        System.assertNotEquals(null, draft.applicationId);

        Onboarding_Application__c app = new Onboarding_Application__c(
            Id = draft.applicationId,
            Account_Type__c = 'Savings'
        );
        Onboarding_Party__c party = new Onboarding_Party__c(
            Id = draft.partyId,
            First_Name__c = 'Seetha',
            Last_Name__c = 'Lakshmi',
            Email__c = 'seetha@example.com',
            Mobile__c = '9999999999'
        );
        RetailApplicationController.Draft saved = RetailApplicationController.saveDraft(
            draft.applicationId,
            app,
            party,
            'account'
        );
        System.assertEquals('account', saved.application.get('Current_Step__c'));

        String passport = EncodingUtil.base64Encode(Blob.valueOf('P<INDDOE<<JOHN\nName: JOHN DOE\nPAN ABCDE1234F'));
        Map<String, Object> uploaded = RetailApplicationController.uploadDocument(
            draft.applicationId,
            draft.partyId,
            'Passport',
            'indian_passport.pdf',
            passport
        );
        Test.stopTest();

        System.assertEquals('Complete', uploaded.get('ocrStatus'));
        System.assertNotEquals(null, uploaded.get('documentId'));
        Map<String, Object> residency = (Map<String, Object>) uploaded.get('residency');
        System.assertEquals('Resident', residency.get('residentStatus'));
        RetailApplicationController.Draft afterPassport = RetailApplicationController.load(draft.applicationId);
        System.assertEquals('John', afterPassport.party.get('First_Name__c'));
        System.assertEquals('Doe', afterPassport.party.get('Last_Name__c'));
    }

    @IsTest
    static void passportAndAddressProofPopulateParty() {
        RetailApplicationController.Draft draft = RetailApplicationController.getOrCreateDraft();
        String passport = EncodingUtil.base64Encode(
            Blob.valueOf(
                'REPUBLIC OF INDIA\nSurname\nLAKSHMI\nGiven Name(s)\nSEETHA V\nNationality INDIAN\n' +
                'Sex F\nDate of Birth 15/08/1990\nPlace of Birth CHENNAI\nAddress\n12 ANNA NAGAR\nCHENNAI\nTAMIL NADU 600040\n' +
                'P<INDLAKSHMI<<SEETHA<V<<<<<<<<\nZ1234567<4IND900815F2508157'
            )
        );
        Test.startTest();
        RetailApplicationController.uploadDocument(
            draft.applicationId,
            draft.partyId,
            'Passport',
            'indian_passport.jpg',
            passport
        );
        RetailApplicationController.uploadDocument(
            draft.applicationId,
            draft.partyId,
            'Address Proof',
            'aadhaar.jpg',
            EncodingUtil.base64Encode(Blob.valueOf('Address\n45 MG ROAD\nBENGALURU\nKARNATAKA 560001'))
        );
        RetailApplicationController.uploadDocument(
            draft.applicationId,
            draft.partyId,
            'Payslip',
            'payslip.txt',
            EncodingUtil.base64Encode(Blob.valueOf('Employer: Infosys\nNet Pay 75000'))
        );
        Test.stopTest();
        RetailApplicationController.Draft loaded = RetailApplicationController.load(draft.applicationId);
        System.assertEquals('Seetha', loaded.party.get('First_Name__c'));
        System.assertEquals('Lakshmi', loaded.party.get('Last_Name__c'));
        System.assertEquals('Female', loaded.party.get('Gender__c'));
        System.assertEquals('560001', loaded.party.get('Residential_Postal_Code__c'));
        System.assertEquals(
            75000,
            Integer.valueOf(String.valueOf(loaded.application.get('Salary_Amount__c')).substringBefore('.'))
        );
    }

    @IsTest
    static void combinedPassportPanPdfPopulatesFromAddressTile() {
        RetailApplicationController.Draft draft = RetailApplicationController.getOrCreateDraft();
        String scan =
            'REPUBLIC OF INDIA\n34-P5 / Surname\nDHAYALAN\nPeTT / Given Name(s)\nHARINI\n' +
            'oprfafla / Date of Birth\n01/07/2003\nPaRT / Sex\nF\nAS358873\n' +
            'PKINDDHAYALAN<<HARINI<<<<<<<<<<<<<<<<<<<<<<<\n' +
            'AS358873<2IND0307019F36042693066696453426<28\n' +
            'D NO 6,PHASE 2, NEAR ADHIYAMAN COLLEGE\nVALLALAR NAGAR,HOSUR, KRISHNAGIRI\n' +
            'PIN:635109, TAMIL NADU, INDIA\nPermanent Account Number Card\nBJRPH7386F';
        Test.startTest();
        Map<String, Object> uploaded = RetailApplicationController.uploadDocument(
            draft.applicationId,
            draft.partyId,
            'Address Proof',
            'Passport&PAN.pdf',
            EncodingUtil.base64Encode(Blob.valueOf(scan))
        );
        Test.stopTest();
        RetailApplicationController.Draft loaded = RetailApplicationController.load(draft.applicationId);
        System.assertEquals('Harini', loaded.party.get('First_Name__c'));
        System.assertEquals('Dhayalan', loaded.party.get('Last_Name__c'));
        System.assertEquals('BJRPH7386F', loaded.party.get('PAN__c'));
        System.assertEquals('635109', loaded.party.get('Residential_Postal_Code__c'));
        System.assertEquals('Resident', loaded.party.get('Resident_Status__c'));
        System.assert(((String) uploaded.get('toastMessage')).contains('PAN'));
        System.assertEquals('2003-07-01', String.valueOf(loaded.party.get('Date_Of_Birth__c')).substring(0, 10));
    }

    @IsTest
    static void clearsAndStartsNewCustomer() {
        RetailApplicationController.Draft first = RetailApplicationController.getOrCreateDraft();
        Onboarding_Party__c party = new Onboarding_Party__c(
            Id = first.partyId,
            First_Name__c = 'Seetha',
            Last_Name__c = 'Lakshmi',
            Email__c = 'seetha@example.com'
        );
        RetailApplicationController.saveDraft(
            first.applicationId,
            new Onboarding_Application__c(Id = first.applicationId),
            party,
            'customer'
        );

        Test.startTest();
        RetailApplicationController.Draft cleared = RetailApplicationController.clearCurrentApplication(
            first.applicationId
        );
        RetailApplicationController.Draft created = RetailApplicationController.startNewApplication();
        Test.stopTest();

        System.assertEquals(first.applicationId, cleared.applicationId);
        System.assertEquals(null, cleared.party.get('First_Name__c'));
        System.assertNotEquals(first.applicationId, created.applicationId);
        System.assertEquals('customer', created.application.get('Current_Step__c'));
        System.assertEquals(
            'Abandoned',
            [SELECT Status__c FROM Onboarding_Application__c WHERE Id = :first.applicationId].Status__c
        );
    }
}