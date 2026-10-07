public with sharing class OnboardingAiService {
    public class Summary {
        public Decimal score;
        public String text;
    }

    public static Summary summarize(Id applicationId) {
        Onboarding_Application__c app = [
            SELECT Id, Channel__c, Legal_Name__c, Email__c, Mobile__c, Nationality__c,
                   Registration_Number__c, Status__c,
                   (SELECT Id, Role__c, Full_Name__c, National_Id__c, Is_PEP__c, Ownership_Percent__c
                    FROM Parties__r),
                   (SELECT Id, Document_Type__c, OCR_Status__c, OCR_Extracted_Text__c, Extracted_Id_Number__c
                    FROM Documents__r)
            FROM Onboarding_Application__c
            WHERE Id = :applicationId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        Decimal score = 20;
        List<String> notes = new List<String>();
        notes.add('Channel: ' + app.Channel__c);
        notes.add('Applicant: ' + app.Legal_Name__c);

        if (String.isBlank(app.Email__c)) {
            score += 10;
            notes.add('Missing email.');
        }
        if (app.Channel__c == 'Corporate' && String.isBlank(app.Registration_Number__c)) {
            score += 15;
            notes.add('Corporate file is missing a registration number.');
        }
        if (app.Parties__r.isEmpty()) {
            score += 15;
            notes.add('No parties captured.');
        }

        Integer pepCount = 0;
        Decimal uboPct = 0;
        for (Onboarding_Party__c party : app.Parties__r) {
            if (party.Is_PEP__c) {
                pepCount++;
            }
            if (party.Role__c == 'UBO' && party.Ownership_Percent__c != null) {
                uboPct += party.Ownership_Percent__c;
            }
        }
        if (pepCount > 0) {
            score += 25;
            notes.add(pepCount + ' PEP party(ies) require enhanced due diligence.');
        }
        if (app.Channel__c == 'Corporate' && uboPct > 0 && uboPct < 75) {
            score += 10;
            notes.add('UBO ownership captured is under 75%. Confirm remaining beneficial owners.');
        }

        Integer ocrReady = 0;
        for (Onboarding_Document__c doc : app.Documents__r) {
            if (doc.OCR_Status__c == 'Complete') {
                ocrReady++;
            }
        }
        if (app.Documents__r.isEmpty()) {
            score += 15;
            notes.add('No KYC/KYB documents uploaded.');
        } else if (ocrReady == 0) {
            score += 8;
            notes.add('Documents are present but OCR is not complete.');
        } else {
            notes.add(ocrReady + ' document(s) have OCR text available for review.');
        }

        if (score > 99) {
            score = 99;
        }

        Summary out = new Summary();
        out.score = score.setScale(2);
        out.text =
            'Onboarding AI review (rules + OCR signals). Einstein GPT/Agentforce will replace this summary when those licenses are enabled in the org.\n\n' +
            String.join(notes, '\n');
        return out;
    }

    public static Onboarding_Application__c persist(Id applicationId) {
        return persist(applicationId, true);
    }

    public static Onboarding_Application__c refreshScore(Id applicationId) {
        return persist(applicationId, false);
    }

    static Onboarding_Application__c persist(Id applicationId, Boolean moveToReview) {
        Summary summary = summarize(applicationId);
        Onboarding_Application__c app = new Onboarding_Application__c(
            Id = applicationId,
            AI_Risk_Score__c = summary.score,
            AI_Risk_Summary__c = summary.text
        );
        if (moveToReview) {
            app.Status__c = 'AI Review';
        }
        Database.update(app, AccessLevel.SYSTEM_MODE);
        return [
            SELECT Id, Name, Channel__c, Status__c, Legal_Name__c, AI_Risk_Score__c, AI_Risk_Summary__c
            FROM Onboarding_Application__c
            WHERE Id = :applicationId
            WITH SYSTEM_MODE
        ];
    }
}