public with sharing class RetailApplicationController {
    public class Draft {
        @AuraEnabled public Map<String, Object> application;
        @AuraEnabled public Map<String, Object> party;
        @AuraEnabled public List<Map<String, Object>> documents;
        @AuraEnabled public String homeCountry;
        @AuraEnabled public Boolean ocrConfigured;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String partyId;
    }

    @AuraEnabled
    public static Draft getOrCreateDraft() {
        List<Onboarding_Application__c> existing = openDrafts();
        if (existing.isEmpty()) {
            return createBlankDraft();
        }
        return load(existing[0].Id);
    }

    @AuraEnabled
    public static Draft startNewApplication() {
        abandonOpenDrafts();
        return createBlankDraft();
    }

    @AuraEnabled
    public static Draft clearCurrentApplication(Id applicationId) {
        if (applicationId == null) {
            return startNewApplication();
        }
        Onboarding_Application__c app = [
            SELECT Id, OwnerId
            FROM Onboarding_Application__c
            WHERE Id = :applicationId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (app.OwnerId != UserInfo.getUserId()) {
            throw handled('You can only clear your own application.');
        }

        List<Onboarding_Document__c> docs = [
            SELECT Id
            FROM Onboarding_Document__c
            WHERE Application__c = :applicationId
            WITH SYSTEM_MODE
        ];
        if (!docs.isEmpty()) {
            Database.delete(docs, AccessLevel.SYSTEM_MODE);
        }

        Onboarding_Application__c resetApp = new Onboarding_Application__c(
            Id = applicationId,
            Status__c = 'Draft',
            Channel__c = 'Retail',
            Legal_Name__c = 'New Retail Applicant',
            Customer_Type__c = 'Individual',
            Number_of_Applicants__c = 1,
            Current_Step__c = 'customer',
            Currency_Code__c = 'INR',
            Account_Type__c = 'Savings',
            Source_System__c = 'Application Entry',
            Onboarding_Channel__c = 'Digital',
            Debit_Card_Required__c = true,
            Internet_Banking__c = true,
            Mobile_Banking__c = true,
            Statement_Mode__c = 'E-Statement',
            Product_Variant__c = 'Regular Savings',
            Completeness_Score__c = 0,
            KYC_Ready__c = false,
            Email__c = null,
            Mobile__c = null,
            Total_Income__c = null,
            Total_Expense__c = null,
            Esign_Consent__c = false,
            Marketing_Consent__c = false,
            Terms_Accepted__c = false,
            Product_Name__c = null,
            Branch_Code__c = null,
            Branch_Name__c = null,
            Operating_Instruction__c = null,
            Mandate_Mode__c = null,
            Mandate_Limit__c = null,
            Salary_Amount__c = null,
            Other_Income__c = null,
            Business_Income__c = null,
            Household_Expense__c = null,
            Medical_Expense__c = null,
            Education_Expense__c = null,
            Employer_Name__c = null,
            Employer_Code__c = null,
            Employment_From__c = null,
            Cheque_Book__c = false,
            Initial_Deposit__c = null,
            Expected_Monthly_Credit__c = null,
            Expected_Monthly_Debit__c = null,
            Nominee_Name__c = null,
            Nominee_Relationship__c = null,
            Nominee_Share__c = null,
            Nominee_DOB__c = null,
            Nominee_Guardian__c = null,
            Collateral_Type__c = null,
            Collateral_Description__c = null,
            Collateral_Value__c = null,
            Related_Party_Name__c = null,
            Related_Party_CIF__c = null,
            Related_Party_Type__c = null,
            Declaration_True_Info__c = false,
            Declaration_AML__c = false,
            Privacy_Consent__c = false,
            WhatsApp_Consent__c = false,
            AI_Risk_Score__c = null,
            AI_Risk_Summary__c = null
        );
        Database.update(resetApp, AccessLevel.SYSTEM_MODE);

        List<Onboarding_Party__c> parties = [
            SELECT Id
            FROM Onboarding_Party__c
            WHERE Application__c = :applicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (!parties.isEmpty()) {
            Onboarding_Party__c resetParty = new Onboarding_Party__c(
                Id = parties[0].Id,
                Name = 'Primary Applicant',
                Full_Name__c = 'Primary Applicant',
                Role__c = 'Primary',
                Resident_Status__c = 'Resident',
                Customer_Category__c = 'INDIVIDUAL',
                Preferred_Language__c = 'English',
                Preferred_Currency__c = 'INR',
                Tax_Resident_India__c = true,
                Country_of_Residence__c = 'India',
                KYC_Risk_Category__c = 'Low',
                Title__c = null,
                First_Name__c = null,
                Middle_Name__c = null,
                Last_Name__c = null,
                Gender__c = null,
                Date_Of_Birth__c = null,
                Resident_Status_Source__c = null,
                Nationality__c = null,
                Passport_Country__c = null,
                Birth_Country__c = null,
                Citizenship_By__c = null,
                Marital_Status__c = null,
                Customer_Segment__c = null,
                Profession__c = null,
                Staff__c = false,
                Is_PEP__c = false,
                Email__c = null,
                Mobile__c = null,
                Phone__c = null,
                National_Id__c = null,
                Name_Local__c = null,
                PAN__c = null,
                Aadhaar_Last4__c = null,
                Father_Spouse_Name__c = null,
                Mother_Maiden_Name__c = null,
                Place_of_Birth__c = null,
                Occupation_Type__c = null,
                Employer_Industry__c = null,
                Source_of_Funds__c = null,
                Purpose_of_Account__c = null,
                Overseas_Tax_Id__c = null,
                Fatca_Us_Person__c = false,
                Crs_Other_Tax_Resident__c = false,
                Residential_Street__c = null,
                Residential_City__c = null,
                Residential_State__c = null,
                Residential_Postal_Code__c = null,
                Mailing_Same__c = false,
                Mailing_Street__c = null,
                Mailing_City__c = null,
                Mailing_State__c = null,
                Mailing_Postal_Code__c = null,
                Emergency_Contact_Name__c = null,
                Emergency_Relationship__c = null,
                Emergency_Mobile__c = null,
                Visa_Type__c = null,
                Visa_Expiry__c = null,
                OCI_PIO__c = false,
                Preferred_Channel__c = null,
                Preferred_Contact_Time__c = null,
                Existing_Customer__c = false
            );
            Database.update(resetParty, AccessLevel.SYSTEM_MODE);
        }
        return load(applicationId);
    }

    @AuraEnabled
    public static Draft load(Id applicationId) {
        if (applicationId == null) {
            return getOrCreateDraft();
        }
        Draft draft = new Draft();
        draft.homeCountry = RetailResidencyService.homeCountryName();
        draft.ocrConfigured = OcrService.isConfigured();
        Onboarding_Application__c app = [
            SELECT Id, Name, Channel__c, Status__c, Legal_Name__c, Email__c, Mobile__c, Customer_Type__c,
                   Number_of_Applicants__c, Current_Step__c, Total_Income__c, Total_Expense__c, Currency_Code__c,
                   Esign_Consent__c, Marketing_Consent__c, Terms_Accepted__c, Product_Name__c, Account_Type__c,
                   Branch_Code__c, Operating_Instruction__c, Mandate_Mode__c, Mandate_Limit__c, Salary_Amount__c,
                   Other_Income__c, Business_Income__c, Household_Expense__c, Medical_Expense__c, Education_Expense__c,
                   Employer_Name__c, Employer_Code__c, Employment_From__c, Cheque_Book__c, Debit_Card_Required__c,
                   Internet_Banking__c, Mobile_Banking__c, Statement_Mode__c, Initial_Deposit__c,
                   Expected_Monthly_Credit__c, Expected_Monthly_Debit__c, Product_Variant__c, Nominee_Name__c,
                   Nominee_Relationship__c, Nominee_Share__c, Nominee_DOB__c, Nominee_Guardian__c, Collateral_Type__c,
                   Collateral_Description__c, Collateral_Value__c, Related_Party_Name__c, Related_Party_CIF__c,
                   Related_Party_Type__c, Completeness_Score__c, KYC_Ready__c, Declaration_True_Info__c,
                   Declaration_AML__c, Privacy_Consent__c, WhatsApp_Consent__c, Branch_Name__c, Onboarding_Channel__c,
                   AI_Risk_Score__c, AI_Risk_Summary__c
            FROM Onboarding_Application__c
            WHERE Id = :applicationId
            WITH SYSTEM_MODE
        ];
        List<Onboarding_Party__c> parties = [
            SELECT Id, Name, Role__c, Full_Name__c, Title__c, First_Name__c, Middle_Name__c, Last_Name__c,
                   Gender__c, Date_Of_Birth__c, Resident_Status__c, Resident_Status_Source__c, Nationality__c,
                   Passport_Country__c, Birth_Country__c, Citizenship_By__c, Marital_Status__c, Customer_Category__c,
                   Customer_Segment__c, Preferred_Language__c, Preferred_Currency__c, Country_of_Residence__c,
                   Profession__c, Staff__c, Is_PEP__c, Email__c, Mobile__c, Phone__c, National_Id__c, Name_Local__c,
                   PAN__c, Aadhaar_Last4__c, Father_Spouse_Name__c, Mother_Maiden_Name__c, Place_of_Birth__c,
                   Occupation_Type__c, Employer_Industry__c, Source_of_Funds__c, Purpose_of_Account__c,
                   Tax_Resident_India__c, Overseas_Tax_Id__c, Fatca_Us_Person__c, Crs_Other_Tax_Resident__c,
                   Residential_Street__c, Residential_City__c, Residential_State__c, Residential_Postal_Code__c,
                   Mailing_Same__c, Mailing_Street__c, Mailing_City__c, Mailing_State__c, Mailing_Postal_Code__c,
                   Emergency_Contact_Name__c, Emergency_Relationship__c, Emergency_Mobile__c, Visa_Type__c,
                   Visa_Expiry__c, OCI_PIO__c, Preferred_Channel__c, Preferred_Contact_Time__c,
                   Existing_Customer__c, KYC_Risk_Category__c
            FROM Onboarding_Party__c
            WHERE Application__c = :applicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        List<Onboarding_Document__c> docs = [
            SELECT Id, Name, Document_Type__c, File_Name__c, OCR_Status__c, Extracted_Country__c,
                   Mapped_Resident_Status__c, Extracted_Name__c, Extracted_Id_Number__c, CreatedDate
            FROM Onboarding_Document__c
            WHERE Application__c = :applicationId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        draft.application = toAuraMap(app);
        draft.party = parties.isEmpty() ? new Map<String, Object>() : toAuraMap(parties[0]);
        draft.documents = new List<Map<String, Object>>();
        for (Onboarding_Document__c doc : docs) {
            draft.documents.add(toAuraMap(doc));
        }
        draft.applicationId = app.Id;
        draft.partyId = parties.isEmpty() ? null : parties[0].Id;
        return draft;
    }

    @AuraEnabled
    public static Draft saveDraft(Id applicationId, Onboarding_Application__c application, Onboarding_Party__c party, String step) {
        if (applicationId == null && application != null) {
            applicationId = application.Id;
        }
        if (applicationId == null) {
            Draft created = getOrCreateDraft();
            applicationId = created.applicationId;
        }
        if (application == null) {
            application = new Onboarding_Application__c();
        }
        application.Id = applicationId;
        application.Current_Step__c = step;
        if (party != null) {
            if (party.Id == null) {
                List<Onboarding_Party__c> existingParty = [
                    SELECT Id FROM Onboarding_Party__c
                    WHERE Application__c = :applicationId
                    WITH SYSTEM_MODE
                    ORDER BY CreatedDate
                    LIMIT 1
                ];
                if (!existingParty.isEmpty()) {
                    party.Id = existingParty[0].Id;
                }
            }
            String composed = joinName(party.Title__c, party.First_Name__c, party.Middle_Name__c, party.Last_Name__c);
            if (String.isNotBlank(composed)) {
                party.Full_Name__c = composed;
                party.Name = composed.left(80);
                application.Legal_Name__c = composed;
            }
            if (String.isNotBlank(party.Email__c)) {
                application.Email__c = party.Email__c;
            }
            if (String.isNotBlank(party.Mobile__c)) {
                application.Mobile__c = party.Mobile__c;
            }
            Decimal income = nz(application.Salary_Amount__c) + nz(application.Other_Income__c) + nz(application.Business_Income__c);
            Decimal expense = nz(application.Household_Expense__c) + nz(application.Medical_Expense__c) + nz(application.Education_Expense__c);
            application.Total_Income__c = income;
            application.Total_Expense__c = expense;
            if (party.Mailing_Same__c == true) {
                party.Mailing_Street__c = party.Residential_Street__c;
                party.Mailing_City__c = party.Residential_City__c;
                party.Mailing_State__c = party.Residential_State__c;
                party.Mailing_Postal_Code__c = party.Residential_Postal_Code__c;
            }
            if (party.Resident_Status__c == 'Resident') {
                party.Tax_Resident_India__c = true;
                if (String.isBlank(party.Country_of_Residence__c)) {
                    party.Country_of_Residence__c = 'India';
                }
                if (String.isBlank(application.Product_Variant__c) || application.Product_Variant__c == 'NRE Savings' || application.Product_Variant__c == 'NRO Savings') {
                    application.Product_Variant__c = 'Regular Savings';
                }
            } else if (party.Resident_Status__c == 'Non Resident') {
                party.Tax_Resident_India__c = false;
                if (String.isBlank(application.Product_Variant__c) || application.Product_Variant__c == 'Regular Savings') {
                    application.Product_Variant__c = 'NRE Savings';
                    application.Account_Type__c = 'Savings';
                }
            }
            if (party.Is_PEP__c == true || party.Fatca_Us_Person__c == true) {
                party.KYC_Risk_Category__c = 'High';
            } else if (party.Resident_Status__c == 'Non Resident' || party.Crs_Other_Tax_Resident__c == true) {
                party.KYC_Risk_Category__c = 'Medium';
            } else if (String.isBlank(party.KYC_Risk_Category__c)) {
                party.KYC_Risk_Category__c = 'Low';
            }
            Integer filled = 0;
            Integer needed = 12;
            if (String.isNotBlank(party.First_Name__c)) filled++;
            if (String.isNotBlank(party.Last_Name__c)) filled++;
            if (party.Date_Of_Birth__c != null) filled++;
            if (String.isNotBlank(party.Email__c)) filled++;
            if (String.isNotBlank(party.Mobile__c)) filled++;
            if (String.isNotBlank(party.Resident_Status__c)) filled++;
            if (String.isNotBlank(party.Residential_Street__c)) filled++;
            if (String.isNotBlank(application.Account_Type__c)) filled++;
            if (String.isNotBlank(party.Occupation_Type__c) || nz(application.Salary_Amount__c) > 0) filled++;
            if (String.isNotBlank(application.Nominee_Name__c)) filled++;
            if (application.Terms_Accepted__c == true) filled++;
            if (application.Declaration_True_Info__c == true) filled++;
            application.Completeness_Score__c = needed == 0 ? 0 : (Decimal.valueOf(filled) / Decimal.valueOf(needed) * 100).setScale(0);
            application.KYC_Ready__c = application.Completeness_Score__c >= 80 && application.Terms_Accepted__c == true;
            if (party.Id != null) {
                Database.update(party, AccessLevel.SYSTEM_MODE);
            }
        }
        Database.update(application, AccessLevel.SYSTEM_MODE);
        return load(applicationId);
    }

    @AuraEnabled
    public static Map<String, Object> classifyNationality(String nationalityOrCountry) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(RetailResidencyService.classifyCountry(nationalityOrCountry))
        );
    }

    @AuraEnabled
    public static Map<String, Object> uploadDocument(
        Id applicationId,
        Id partyId,
        String documentType,
        String fileName,
        String base64Data
    ) {
        if (applicationId == null || partyId == null) {
            throw handled('Save or reload the application, then upload the document.');
        }
        try {
            RetailDocumentIntake.IntakeResult result = RetailDocumentIntake.ingest(
                applicationId,
                partyId,
                documentType,
                fileName,
                base64Data
            );
            return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(result));
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    static List<Onboarding_Application__c> openDrafts() {
        return [
            SELECT Id
            FROM Onboarding_Application__c
            WHERE Channel__c = 'Retail'
              AND OwnerId = :UserInfo.getUserId()
              AND Status__c IN ('Draft', 'Submitted', 'Documents')
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    static void abandonOpenDrafts() {
        List<Onboarding_Application__c> existing = openDrafts();
        for (Onboarding_Application__c row : existing) {
            row.Status__c = 'Abandoned';
        }
        if (!existing.isEmpty()) {
            Database.update(existing, AccessLevel.SYSTEM_MODE);
        }
    }

    static Draft createBlankDraft() {
        Onboarding_Application__c app = new Onboarding_Application__c(
            Channel__c = 'Retail',
            Status__c = 'Draft',
            Legal_Name__c = 'New Retail Applicant',
            Customer_Type__c = 'Individual',
            Number_of_Applicants__c = 1,
            Current_Step__c = 'customer',
            Currency_Code__c = 'INR',
            Account_Type__c = 'Savings',
            Source_System__c = 'Application Entry',
            Onboarding_Channel__c = 'Digital',
            Debit_Card_Required__c = true,
            Internet_Banking__c = true,
            Mobile_Banking__c = true,
            Statement_Mode__c = 'E-Statement',
            Product_Variant__c = 'Regular Savings'
        );
        Database.insert(app, AccessLevel.SYSTEM_MODE);
        Onboarding_Party__c party = new Onboarding_Party__c(
            Application__c = app.Id,
            Name = 'Primary Applicant',
            Full_Name__c = 'Primary Applicant',
            Role__c = 'Primary',
            Resident_Status__c = 'Resident',
            Customer_Category__c = 'INDIVIDUAL',
            Preferred_Language__c = 'English',
            Preferred_Currency__c = 'INR',
            Tax_Resident_India__c = true,
            Country_of_Residence__c = 'India',
            KYC_Risk_Category__c = 'Low'
        );
        Database.insert(party, AccessLevel.SYSTEM_MODE);
        return load(app.Id);
    }

    static AuraHandledException handled(String message) {
        String text = String.isBlank(message) ? 'Request failed.' : message.left(1000);
        AuraHandledException ex = new AuraHandledException(text);
        ex.setMessage(text);
        return ex;
    }

    static Map<String, Object> toAuraMap(SObject rec) {
        return rec == null ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(rec));
    }

    static String joinName(String title, String firstName, String middleName, String lastName) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(title)) {
            parts.add(title);
        }
        if (String.isNotBlank(firstName)) {
            parts.add(firstName);
        }
        if (String.isNotBlank(middleName)) {
            parts.add(middleName);
        }
        if (String.isNotBlank(lastName)) {
            parts.add(lastName);
        }
        return String.join(parts, ' ');
    }

    static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }
}