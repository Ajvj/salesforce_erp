public with sharing class RetailDocumentIntake {
    public class IntakeResult {
        @AuraEnabled public String documentId;
        @AuraEnabled public RetailResidencyService.Classification residency;
        @AuraEnabled public String extractedName;
        @AuraEnabled public String extractedId;
        @AuraEnabled public String extractedPan;
        @AuraEnabled public Date extractedExpiry;
        @AuraEnabled public Date extractedDob;
        @AuraEnabled public String ocrStatus;
        @AuraEnabled public String ocrMessage;
        @AuraEnabled public Decimal salaryAmount;
        @AuraEnabled public String employerName;
        @AuraEnabled public Decimal aiScore;
        @AuraEnabled public String aiSummary;
        @AuraEnabled public String toastMessage;
    }

    public static IntakeResult ingest(Id applicationId, Id partyId, String documentType, String fileName, String base64Data) {
        if (applicationId == null) {
            throw fail('Application is required');
        }
        if (String.isBlank(base64Data)) {
            throw fail('File data is required');
        }
        if (base64Data.length() > 1600000) {
            throw fail('The scan is too large. Upload a PDF or JPG under 1 MB.');
        }
        Blob body;
        try {
            body = EncodingUtil.base64Decode(base64Data);
        } catch (Exception e) {
            throw fail('The file could not be read. Try exporting it as a PDF or JPG and upload again.');
        }
        OcrService.Result ocr;
        try {
            ocr = OcrService.extract(body, fileName, base64Data);
        } catch (Exception e) {
            ocr = new OcrService.Result();
            ocr.success = true;
            ocr.status = 'Complete';
            ocr.message = 'The file was stored. Document reading failed: ' + e.getMessage();
            ocr.extractedText = fileName;
        }
        String combinedText = ((ocr.extractedText == null ? '' : ocr.extractedText) + ' ' + (fileName == null ? '' : fileName));

        ContentVersion cv = new ContentVersion(
            Title = String.isBlank(fileName) ? 'document' : fileName,
            PathOnClient = String.isBlank(fileName) ? 'document.bin' : fileName.replaceAll('[^A-Za-z0-9._-]', '_'),
            VersionData = body
        );
        if (Network.getNetworkId() != null) {
            cv.NetworkId = Network.getNetworkId();
        }
        try {
            Database.insert(cv, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            throw fail('The file could not be stored. ' + e.getMessage());
        }
        cv = [
            SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE
        ];

        Onboarding_Document__c doc = new Onboarding_Document__c(
            Application__c = applicationId,
            Party__c = partyId,
            Document_Type__c = String.isBlank(documentType) ? 'Other' : documentType,
            File_Name__c = fileName,
            Content_Document_Id__c = cv.ContentDocumentId,
            OCR_Status__c = String.isBlank(ocr.status) ? 'Complete' : ocr.status,
            OCR_Extracted_Text__c = String.isBlank(ocr.extractedText)
                ? ocr.message
                : ocr.extractedText.left(32000),
            OCR_Raw_JSON__c = String.isBlank(ocr.rawJson) ? null : ocr.rawJson.left(131000),
            Extracted_Name__c = ocr.extractedName,
            Extracted_Id_Number__c = ocr.extractedId,
            Extracted_Expiry__c = ocr.extractedExpiry
        );

        IntakeResult result = new IntakeResult();
        result.ocrStatus = ocr.status;
        result.ocrMessage = ocr.message;
        result.extractedName = ocr.extractedName;
        result.extractedId = ocr.extractedId;
        result.extractedPan = ocr.extractedPan;
        result.extractedExpiry = ocr.extractedExpiry;
        result.extractedDob = ocr.extractedDob;

        String typeKey = documentType == null ? '' : documentType.toLowerCase();
        String nameKey = fileName == null ? '' : fileName.toLowerCase();
        if (typeKey.contains('photo') && nameKey.contains('passport')) {
            typeKey = 'passport';
            doc.Document_Type__c = 'Passport';
        }
        Boolean passportLike =
            typeKey.contains('passport') ||
            typeKey.contains('national id') ||
            typeKey.contains('emirates') ||
            nameKey.contains('passport') ||
            looksLikePassport(ocr.extractedText);
        Boolean panLike = typeKey.contains('pan') || nameKey.contains('pan') || String.isNotBlank(ocr.extractedPan);
        if (passportLike && !typeKey.contains('passport')) {
            doc.Document_Type__c = 'Passport';
        }

        if (passportLike) {
            RetailResidencyService.Classification residency = RetailResidencyService.classifyPassport(combinedText, fileName);
            result.residency = residency;
            if (residency != null && String.isNotBlank(residency.residentStatus)) {
                doc.Extracted_Country__c = String.isBlank(residency.countryName) ? residency.countryCode : residency.countryName;
                doc.Extracted_Nationality__c = residency.nationality;
                doc.Mapped_Resident_Status__c = residency.residentStatus;
            }
            applyPartyFromDocument(partyId, residency, ocr);
        } else if (!typeKey.contains('payslip') && !typeKey.contains('salary')) {
            applyPartyFromDocument(partyId, null, ocr);
        }

        if (typeKey.contains('payslip') || typeKey.contains('salary')) {
            Decimal salary = RetailResidencyService.parseAmount(
                combinedText,
                new List<String>{ 'net pay', 'net salary', 'gross pay', 'basic salary', 'salary', 'pay' }
            );
            String employer = RetailResidencyService.parseEmployer(combinedText);
            result.salaryAmount = salary;
            result.employerName = employer;
            applyPayslip(applicationId, salary, employer);
            result.toastMessage = salary == null
                ? 'Payslip stored. Salary was not read — enter it on Financial Details.'
                : 'Payslip uploaded. Salary ' + String.valueOf(salary) + ' was populated on Financial Details.';
        } else {
            result.toastMessage = buildKycToast(passportLike, panLike, typeKey, ocr, result.residency);
        }

        Database.insert(doc, AccessLevel.SYSTEM_MODE);
        result.documentId = doc.Id;
        try {
            Database.insert(
                new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = doc.Id,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            // File is stored on ContentVersion even if the record link is denied.
        }
        try {
            Onboarding_Application__c scored = OnboardingAiService.refreshScore(applicationId);
            result.aiScore = scored.AI_Risk_Score__c;
            result.aiSummary = scored.AI_Risk_Summary__c;
            if (String.isNotBlank(result.toastMessage) && result.aiScore != null) {
                result.toastMessage += ' AI risk score ' + String.valueOf(result.aiScore) + '.';
            }
        } catch (Exception e) {
            // OCR mapping still stands if AI scoring is unavailable.
        }
        return result;
    }

    static void applyPan(Id partyId, OcrService.Result ocr) {
        if (partyId == null || ocr == null || (String.isBlank(ocr.extractedPan) && String.isBlank(ocr.extractedId))) {
            return;
        }
        Onboarding_Party__c party = new Onboarding_Party__c(Id = partyId);
        party.PAN__c = String.isNotBlank(ocr.extractedPan) ? ocr.extractedPan : ocr.extractedId;
        Database.update(party, AccessLevel.SYSTEM_MODE);
    }

    static void applyIdentityHints(Id partyId, OcrService.Result ocr) {
        applyPartyFromDocument(partyId, null, ocr);
    }

    static void applyPartyFromDocument(Id partyId, RetailResidencyService.Classification residency, OcrService.Result ocr) {
        if (partyId == null) {
            return;
        }
        Onboarding_Party__c party = new Onboarding_Party__c(Id = partyId);
        Boolean changed = false;
        if (residency != null && String.isNotBlank(residency.residentStatus)) {
            party.Resident_Status__c = residency.residentStatus;
            party.Resident_Status_Source__c = 'Passport';
            party.Passport_Country__c = String.isBlank(residency.countryName) ? residency.countryCode : residency.countryName;
            party.Nationality__c = residency.homeCountry ? RetailResidencyService.homeCountryName() : residency.nationality;
            party.Birth_Country__c = residency.homeCountry ? RetailResidencyService.homeCountryCode() : residency.countryCode;
            party.Tax_Resident_India__c = residency.homeCountry;
            party.Country_of_Residence__c = residency.homeCountry
                ? RetailResidencyService.homeCountryName()
                : (String.isBlank(residency.countryName) ? residency.countryCode : residency.countryName);
            party.KYC_Risk_Category__c = residency.homeCountry ? 'Low' : 'Medium';
            changed = true;
        }
        if (ocr != null) {
            String firstName = ocr.extractedFirstName;
            String lastName = ocr.extractedLastName;
            String middleName;
            if (String.isBlank(firstName) && String.isNotBlank(ocr.extractedName)) {
                List<String> parts = ocr.extractedName.trim().split('\\s+');
                if (!parts.isEmpty()) {
                    firstName = parts[0];
                    lastName = parts.size() > 1 ? parts[parts.size() - 1] : parts[0];
                    if (parts.size() > 2) {
                        List<String> mid = new List<String>();
                        for (Integer i = 1; i < parts.size() - 1; i++) {
                            mid.add(parts[i]);
                        }
                        middleName = String.join(mid, ' ');
                    }
                }
            } else if (String.isNotBlank(firstName)) {
                String givenNames = firstName.trim();
                List<String> given = givenNames.split('\\s+');
                firstName = given[0];
                if (given.size() > 1) {
                    middleName = givenNames.substring(given[0].length()).trim();
                }
            }
            if (String.isNotBlank(firstName)) {
                party.First_Name__c = firstName.left(80);
                changed = true;
            }
            if (String.isNotBlank(middleName)) {
                party.Middle_Name__c = middleName.left(80);
                changed = true;
            }
            if (String.isNotBlank(lastName)) {
                party.Last_Name__c = lastName.left(80);
                changed = true;
            }
            String fullName = ((firstName == null ? '' : firstName) +
                ' ' +
                (middleName == null ? '' : middleName) +
                ' ' +
                (lastName == null ? '' : lastName)).replaceAll('\\s+', ' ').trim();
            if (String.isNotBlank(fullName)) {
                party.Full_Name__c = fullName.left(255);
                party.Name = fullName.left(80);
            }
            if (String.isNotBlank(ocr.extractedId)) {
                party.National_Id__c = ocr.extractedId;
                changed = true;
            }
            if (ocr.extractedDob != null) {
                party.Date_Of_Birth__c = ocr.extractedDob;
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedGender)) {
                party.Gender__c = ocr.extractedGender;
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedPlaceOfBirth)) {
                party.Place_of_Birth__c = ocr.extractedPlaceOfBirth.left(80);
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedStreet)) {
                party.Residential_Street__c = ocr.extractedStreet.left(255);
                party.Mailing_Same__c = true;
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedCity)) {
                party.Residential_City__c = ocr.extractedCity.left(80);
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedState)) {
                party.Residential_State__c = ocr.extractedState.left(80);
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedPostal)) {
                party.Residential_Postal_Code__c = ocr.extractedPostal.left(20);
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedPan)) {
                party.PAN__c = ocr.extractedPan;
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedFatherName)) {
                party.Father_Spouse_Name__c = ocr.extractedFatherName.left(80);
                changed = true;
            }
            if (String.isNotBlank(ocr.extractedMotherName)) {
                party.Mother_Maiden_Name__c = ocr.extractedMotherName.left(80);
                changed = true;
            }
        }
        if (changed) {
            Database.update(party, AccessLevel.SYSTEM_MODE);
        }
    }

    static void applyPayslip(Id applicationId, Decimal salary, String employer) {
        Onboarding_Application__c app = new Onboarding_Application__c(Id = applicationId);
        if (salary != null) {
            app.Salary_Amount__c = salary;
            Decimal otherInc = 0;
            Decimal business = 0;
            List<Onboarding_Application__c> current = [
                SELECT Other_Income__c, Business_Income__c, Household_Expense__c, Medical_Expense__c, Education_Expense__c
                FROM Onboarding_Application__c
                WHERE Id = :applicationId
                WITH SYSTEM_MODE
            ];
            if (!current.isEmpty()) {
                otherInc = current[0].Other_Income__c == null ? 0 : current[0].Other_Income__c;
                business = current[0].Business_Income__c == null ? 0 : current[0].Business_Income__c;
                Decimal hh = current[0].Household_Expense__c == null ? 0 : current[0].Household_Expense__c;
                Decimal med = current[0].Medical_Expense__c == null ? 0 : current[0].Medical_Expense__c;
                Decimal edu = current[0].Education_Expense__c == null ? 0 : current[0].Education_Expense__c;
                app.Total_Income__c = salary + otherInc + business;
                app.Total_Expense__c = hh + med + edu;
            } else {
                app.Total_Income__c = salary;
            }
        }
        if (String.isNotBlank(employer)) {
            app.Employer_Name__c = employer.left(255);
            app.Employer_Code__c = employer.left(40).toUpperCase();
        }
        Database.update(app, AccessLevel.SYSTEM_MODE);
    }

    static Boolean looksLikePassport(String text) {
        if (String.isBlank(text)) {
            return false;
        }
        String upper = text.toUpperCase();
        return upper.contains('P<') ||
            upper.contains('PKIND') ||
            (upper.contains('SURNAME') && upper.contains('DATE OF BIRTH')) ||
            (upper.contains('REPUBLIC OF INDIA') && (upper.contains('GIVEN NAME') || upper.contains('PASSPORT')));
    }

    static String buildKycToast(
        Boolean passportLike,
        Boolean panLike,
        String typeKey,
        OcrService.Result ocr,
        RetailResidencyService.Classification residency
    ) {
        List<String> parts = new List<String>();
        if (residency != null && String.isNotBlank(residency.reason)) {
            parts.add(residency.reason);
        } else if (passportLike) {
            parts.add('Passport stored. Enter nationality if Resident / Non Resident was not set.');
        }
        if (ocr != null) {
            if (String.isNotBlank(ocr.extractedFirstName) || String.isNotBlank(ocr.extractedLastName) || String.isNotBlank(ocr.extractedName)) {
                parts.add('Name was populated from the document.');
            }
            if (ocr.extractedDob != null) {
                parts.add('Date of birth was populated.');
            }
            if (String.isNotBlank(ocr.extractedStreet) || String.isNotBlank(ocr.extractedPostal)) {
                parts.add('Residential address was populated.');
            }
            if (String.isNotBlank(ocr.extractedPan)) {
                parts.add('PAN captured: ' + ocr.extractedPan + '.');
            } else if (panLike) {
                parts.add('Enter PAN if it was not read from the file.');
            }
        }
        if (parts.isEmpty()) {
            if (typeKey != null && typeKey.contains('address')) {
                return 'Address proof stored. Enter the address if it was not read from the file.';
            }
            return ocr != null && String.isNotBlank(ocr.message) ? ocr.message : 'Document stored and sent through document AI.';
        }
        return String.join(parts, ' ');
    }

    static AuraHandledException fail(String message) {
        String text = String.isBlank(message) ? 'Upload failed.' : message.left(1000);
        AuraHandledException ex = new AuraHandledException(text);
        ex.setMessage(text);
        return ex;
    }
}