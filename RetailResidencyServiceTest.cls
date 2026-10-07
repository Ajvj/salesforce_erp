@IsTest
private class RetailResidencyServiceTest {
    @IsTest
    static void indianPassportIsResident() {
        RetailResidencyService.Classification fromName = RetailResidencyService.classifyCountry('India');
        RetailResidencyService.Classification fromMrz = RetailResidencyService.classifyPassport('P<INDDOE<<JOHN', 'passport.png');
        RetailResidencyService.Classification fromFile = RetailResidencyService.classifyPassport('', 'indian_passport.pdf');
        System.assertEquals('Resident', fromName.residentStatus);
        System.assertEquals(true, fromName.homeCountry);
        System.assertEquals('Resident', fromMrz.residentStatus);
        System.assertEquals('Resident', fromFile.residentStatus);
    }

    @IsTest
    static void foreignPassportIsNonResident() {
        RetailResidencyService.Classification gb = RetailResidencyService.classifyCountry('GB');
        RetailResidencyService.Classification uk = RetailResidencyService.classifyPassport('NATIONALITY BRITISH\nP<GBRSMITH<<JOHN', 'uk_passport.pdf');
        System.assertEquals('Non Resident', gb.residentStatus);
        System.assertEquals(false, gb.homeCountry);
        System.assertEquals('Non Resident', uk.residentStatus);
        System.assert(uk.reason.contains('foreign national'));
    }

    @IsTest
    static void payslipParsesSalaryAndEmployer() {
        Decimal salary = RetailResidencyService.parseAmount(
            'Net Pay: 150,000.00\nEmployer: ORACLE',
            new List<String>{ 'net pay', 'salary' }
        );
        String employer = RetailResidencyService.parseEmployer('Employer: ORACLE INDIA');
        System.assertEquals(150000, salary);
        System.assert(employer.contains('ORACLE'));
    }

    @IsTest
    static void draftSaveAndNationalityClassify() {
        Onboarding_Application__c app = new Onboarding_Application__c(
            Channel__c = 'Retail',
            Status__c = 'Draft',
            Legal_Name__c = 'Temp',
            Customer_Type__c = 'Individual'
        );
        insert as system app;
        Onboarding_Party__c party = new Onboarding_Party__c(
            Application__c = app.Id,
            Name = 'Temp',
            Full_Name__c = 'Temp',
            Role__c = 'Primary'
        );
        insert as system party;
        party.First_Name__c = 'John';
        party.Last_Name__c = 'Smith';
        party.Title__c = 'Mr.';
        Test.startTest();
        RetailApplicationController.Draft saved = RetailApplicationController.saveDraft(app.Id, app, party, 'customer');
        Map<String, Object> cls = RetailApplicationController.classifyNationality('India');
        Test.stopTest();
        System.assertEquals('Mr. John Smith', (String) saved.party.get('Full_Name__c'));
        System.assertEquals('Resident', (String) cls.get('residentStatus'));
        System.assertEquals('customer', (String) saved.application.get('Current_Step__c'));
    }

    @IsTest
    static void passportFilenameMarksResidentWithoutOcr() {
        Onboarding_Application__c app = new Onboarding_Application__c(
            Channel__c = 'Retail',
            Status__c = 'Draft',
            Legal_Name__c = 'Applicant'
        );
        insert as system app;
        Onboarding_Party__c party = new Onboarding_Party__c(
            Application__c = app.Id,
            Name = 'Applicant',
            Full_Name__c = 'Applicant',
            Role__c = 'Primary'
        );
        insert as system party;
        Test.startTest();
        RetailDocumentIntake.IntakeResult india = RetailDocumentIntake.ingest(
            app.Id,
            party.Id,
            'Passport',
            'indian_passport.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('sample'))
        );
        RetailDocumentIntake.IntakeResult uk = RetailDocumentIntake.ingest(
            app.Id,
            party.Id,
            'Passport',
            'uk_passport_british.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('sample'))
        );
        Test.stopTest();
        System.assertEquals('Resident', india.residency.residentStatus);
        Onboarding_Party__c afterUk = [
            SELECT Resident_Status__c FROM Onboarding_Party__c WHERE Id = :party.Id WITH SYSTEM_MODE
        ];
        System.assertEquals('Non Resident', afterUk.Resident_Status__c);
    }
}