@RestResource(urlMapping='/onboarding/v1/*')
global with sharing class OnboardingApi {
    global class PartyInput {
        public String role;
        public String fullName;
        public Date dateOfBirth;
        public String nationalId;
        public Decimal ownershipPercent;
        public String email;
        public Boolean isPep;
    }

    global class ApplicationInput {
        public String channel;
        public String legalName;
        public String email;
        public String mobile;
        public String nationality;
        public String registrationNumber;
        public String externalReference;
        public String sourceSystem;
        public List<PartyInput> parties;
    }

    global class DocumentInput {
        public String documentType;
        public String fileName;
        public String base64Data;
        public Id partyId;
        public Boolean runOcr;
    }

    @HttpGet
    global static void doGet() {
        try {
            RestRequest req = RestContext.request;
            String path = relativePath(req);
            if (path == 'health' || String.isBlank(path)) {
                write(200, health());
                return;
            }
            if (path.startsWith('applications/')) {
                String appId = path.substringAfter('applications/');
                if (appId.contains('/')) {
                    write(400, err('Use GET /onboarding/v1/applications/{id}'));
                    return;
                }
                write(200, getApplication(appId));
                return;
            }
            write(404, err('Unknown GET route: ' + path));
        } catch (Exception e) {
            write(400, err(e.getMessage()));
        }
    }

    @HttpPost
    global static void doPost() {
        try {
            RestRequest req = RestContext.request;
            String path = relativePath(req);
            String body = req.requestBody == null ? '' : req.requestBody.toString();
            if (path == 'applications' || path == 'applications/') {
                ApplicationInput input = (ApplicationInput) JSON.deserialize(body, ApplicationInput.class);
                write(201, createApplication(input));
                return;
            }
            if (path.startsWith('applications/') && path.endsWith('/documents')) {
                Id appId = (Id) path.substringBetween('applications/', '/documents');
                DocumentInput input = (DocumentInput) JSON.deserialize(body, DocumentInput.class);
                write(201, addDocument(appId, input));
                return;
            }
            if (path.startsWith('applications/') && path.endsWith('/ai/summarize')) {
                Id appId = (Id) path.substringBetween('applications/', '/ai/summarize');
                write(200, OnboardingAiService.persist(appId));
                return;
            }
            write(404, err('Unknown POST route: ' + path));
        } catch (Exception e) {
            write(400, err(e.getMessage()));
        }
    }

    static String relativePath(RestRequest req) {
        String uri = req.requestURI == null ? '' : req.requestURI;
        if (uri.contains('/onboarding/v1/')) {
            return uri.substringAfter('/onboarding/v1/');
        }
        return uri.replace('/onboarding/v1', '').removeStart('/');
    }

    public static Map<String, Object> health() {
        return new Map<String, Object>{
            'status' => 'ok',
            'orgId' => UserInfo.getOrganizationId(),
            'username' => UserInfo.getUserName(),
            'ocrConfigured' => OcrService.isConfigured(),
            'apiBase' => '/services/apexrest/onboarding/v1'
        };
    }

    public static Onboarding_Application__c createApplication(ApplicationInput input) {
        if (input == null || String.isBlank(input.legalName)) {
            throw new AuraHandledException('legalName is required');
        }
        String channel = String.isBlank(input.channel) ? 'Retail' : input.channel;
        Onboarding_Application__c app = new Onboarding_Application__c(
            Channel__c = channel,
            Status__c = 'Submitted',
            Legal_Name__c = input.legalName,
            Email__c = input.email,
            Mobile__c = input.mobile,
            Nationality__c = input.nationality,
            Registration_Number__c = input.registrationNumber,
            External_Reference__c = input.externalReference,
            Source_System__c = String.isBlank(input.sourceSystem) ? 'API' : input.sourceSystem,
            Submitted_At__c = System.now()
        );
        insert app;

        List<Onboarding_Party__c> parties = new List<Onboarding_Party__c>();
        if (input.parties != null) {
            for (PartyInput party : input.parties) {
                if (party == null || String.isBlank(party.fullName)) {
                    continue;
                }
                parties.add(new Onboarding_Party__c(
                    Application__c = app.Id,
                    Name = party.fullName,
                    Full_Name__c = party.fullName,
                    Role__c = String.isBlank(party.role) ? 'Primary' : party.role,
                    Date_Of_Birth__c = party.dateOfBirth,
                    National_Id__c = party.nationalId,
                    Ownership_Percent__c = party.ownershipPercent,
                    Email__c = party.email,
                    Is_PEP__c = party.isPep == true
                ));
            }
        }
        if (!parties.isEmpty()) {
            insert parties;
        }
        return getApplication(app.Id);
    }

    public static Onboarding_Application__c getApplication(String appId) {
        return [
            SELECT Id, Name, Channel__c, Status__c, Legal_Name__c, Email__c, Mobile__c, Nationality__c,
                   Registration_Number__c, External_Reference__c, Source_System__c, Submitted_At__c,
                   AI_Risk_Score__c, AI_Risk_Summary__c,
                   (SELECT Id, Name, Role__c, Full_Name__c, Date_Of_Birth__c, National_Id__c,
                           Ownership_Percent__c, Email__c, Is_PEP__c
                    FROM Parties__r),
                   (SELECT Id, Name, Document_Type__c, File_Name__c, OCR_Status__c, Extracted_Name__c,
                           Extracted_Id_Number__c, Extracted_Expiry__c, Content_Document_Id__c
                    FROM Documents__r)
            FROM Onboarding_Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
    }

    public static Onboarding_Document__c addDocument(Id appId, DocumentInput input) {
        if (input == null || String.isBlank(input.base64Data)) {
            throw new AuraHandledException('base64Data is required');
        }
        String fileName = String.isBlank(input.fileName) ? 'document.bin' : input.fileName;
        Blob fileBody = EncodingUtil.base64Decode(input.base64Data);

        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = fileBody
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Onboarding_Document__c doc = new Onboarding_Document__c(
            Application__c = appId,
            Party__c = input.partyId,
            Document_Type__c = String.isBlank(input.documentType) ? 'Other' : input.documentType,
            File_Name__c = fileName,
            Content_Document_Id__c = cv.ContentDocumentId,
            OCR_Status__c = 'Pending'
        );

        Boolean runOcr = input.runOcr != false;
        if (runOcr) {
            OcrService.Result ocr = OcrService.extract(fileBody, fileName);
            doc.OCR_Status__c = ocr.status;
            doc.OCR_Extracted_Text__c = String.isBlank(ocr.extractedText) ? ocr.message : ocr.extractedText;
            doc.OCR_Raw_JSON__c = ocr.rawJson;
            doc.Extracted_Name__c = ocr.extractedName;
            doc.Extracted_Id_Number__c = ocr.extractedId;
            doc.Extracted_Expiry__c = ocr.extractedExpiry;
        }
        insert doc;

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = doc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return [
            SELECT Id, Name, Document_Type__c, File_Name__c, OCR_Status__c, OCR_Extracted_Text__c,
                   Extracted_Name__c, Extracted_Id_Number__c, Content_Document_Id__c
            FROM Onboarding_Document__c
            WHERE Id = :doc.Id
        ];
    }

    static void write(Integer statusCode, Object payload) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }

    static Map<String, String> err(String message) {
        return new Map<String, String>{ 'error' => message };
    }
}