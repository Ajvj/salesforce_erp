public with sharing class DigitalSignatureController {
    static AuraHandledException handled(String message) {
        String text = String.isBlank(message) ? 'Request failed.' : message.left(1000);
        AuraHandledException ex = new AuraHandledException(text);
        ex.setMessage(text);
        return ex;
    }

    static Map<String, Object> toMap(SObject rec) {
        return rec == null ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(rec));
    }

    static List<Map<String, Object>> toMapList(List<SObject> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        for (SObject row : rows) {
            out.add(toMap(row));
        }
        return out;
    }

    static Map<String, Object> payload(Signature_Request__c request) {
        Id requestId = request.Id;
        List<Signature_Document__c> docs = [
            SELECT Id, Name, File_Name__c, Content_Document_Id__c, Content_Hash__c, Sort_Order__c
            FROM Signature_Document__c
            WHERE Request__c = :requestId
            WITH SYSTEM_MODE
            ORDER BY Sort_Order__c, CreatedDate
        ];
        List<Signature_Signer__c> signers = [
            SELECT Id, Name, Full_Name__c, Email__c, Mobile__c, Role__c, Signing_Order__c, Status__c,
                   Access_Code__c, Otp_Expires_At__c, Signed_At__c, Signature_Type__c, Consent_Accepted__c
            FROM Signature_Signer__c
            WHERE Request__c = :requestId
            WITH SYSTEM_MODE
            ORDER BY Signing_Order__c, CreatedDate
        ];
        List<Signature_Event__c> events = [
            SELECT Id, Name, Event_Type__c, Actor__c, Document_Hash__c, Signature_Hash__c,
                   Occurred_At__c, Notes__c, Signer__c
            FROM Signature_Event__c
            WHERE Request__c = :requestId
            WITH SYSTEM_MODE
            ORDER BY Occurred_At__c DESC, CreatedDate DESC
        ];
        return new Map<String, Object>{
            'request' => toMap(request),
            'requestId' => request.Id,
            'documents' => toMapList(docs),
            'signers' => toMapList(signers),
            'events' => toMapList(events)
        };
    }

    static Datetime parseWhen(String raw) {
        if (String.isBlank(raw) || raw.equalsIgnoreCase('undefined') || raw.equalsIgnoreCase('null')) {
            return null;
        }
        String text = raw.trim();
        try {
            Boolean localPicker = text.contains('T') && !text.endsWith('Z') && !text.contains('+') && text.length() <= 19;
            if (localPicker) {
                String local = text.replace('T', ' ');
                if (local.length() == 16) {
                    local += ':00';
                }
                return Datetime.valueOf(local);
            }
            if (!text.contains('T') && text.length() >= 19) {
                return Datetime.valueOf(text.left(19));
            }
            String iso = text.replace('+0000', 'Z');
            if (!iso.endsWith('Z') && iso.contains('T')) {
                iso += 'Z';
            }
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            throw handled('Enter a valid expiry date and time using the date picker.');
        }
    }

    static String productOf(String productType) {
        Set<String> allowed = new Set<String>{ 'Account', 'Loan', 'Mandate', 'Guarantee', 'Other' };
        return allowed.contains(productType) ? productType : 'Other';
    }

    @AuraEnabled
    public static Map<String, Object> createRequest(String title, String productType, String branchCode, String expiresOn) {
        try {
            if (String.isBlank(title)) {
                throw handled('Enter a request title.');
            }
            Datetime expires = parseWhen(expiresOn);
            if (expires == null) {
                expires = System.now().addDays(2);
            }
            Signature_Request__c request = new Signature_Request__c(
                Title__c = title.trim(),
                Product_Type__c = productOf(productType),
                Branch_Code__c = branchCode,
                Status__c = DigitalSignatureService.STATUS_DRAFT,
                Expires_On__c = expires,
                Document_Count__c = 0,
                Signer_Count__c = 0,
                Signed_Count__c = 0
            );
            Database.insert(request, AccessLevel.SYSTEM_MODE);
            DigitalSignatureService.writeEvent(request.Id, null, 'Created', null, null, title);
            return payload(DigitalSignatureService.requireRequest(request.Id));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> loadRequest(Id requestId) {
        try {
            Signature_Request__c request = DigitalSignatureService.requireRequest(requestId);
            if (DigitalSignatureService.isExpired(request)) {
                DigitalSignatureService.markExpired(request);
                request = DigitalSignatureService.requireRequest(requestId);
            }
            return payload(request);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> saveDraft(Id requestId, String title, String productType, String branchCode, String expiresOn) {
        try {
            Signature_Request__c request = DigitalSignatureService.requireRequest(requestId);
            if (request.Status__c != DigitalSignatureService.STATUS_DRAFT) {
                throw handled('Only a draft can be edited.');
            }
            if (String.isBlank(title)) {
                throw handled('Enter a request title.');
            }
            request.Title__c = title.trim();
            request.Product_Type__c = productOf(productType);
            request.Branch_Code__c = branchCode;
            Datetime expires = parseWhen(expiresOn);
            if (expires != null) {
                request.Expires_On__c = expires;
            }
            Database.update(request, AccessLevel.SYSTEM_MODE);
            return payload(DigitalSignatureService.requireRequest(requestId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> addDocument(Id requestId, String fileName, String base64Data) {
        try {
            Signature_Request__c request = DigitalSignatureService.requireRequest(requestId);
            if (request.Status__c != DigitalSignatureService.STATUS_DRAFT) {
                throw handled('Documents can be added only while the request is a draft.');
            }
            if (String.isBlank(base64Data)) {
                throw handled('Choose a file to attach.');
            }
            if (base64Data.length() > 1600000) {
                throw handled('The file is too large. Attach a PDF or image under 1 MB.');
            }
            String lower = String.isBlank(fileName) ? '' : fileName.toLowerCase();
            if (!(lower.endsWith('.pdf') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.txt'))) {
                throw handled('Attach a PDF, JPG, PNG, or TXT file.');
            }
            Blob body = EncodingUtil.base64Decode(base64Data);
            ContentVersion cv = new ContentVersion(
                Title = String.isBlank(fileName) ? 'document' : fileName,
                PathOnClient = String.isBlank(fileName) ? 'document.bin' : fileName.replaceAll('[^A-Za-z0-9._-]', '_'),
                VersionData = body
            );
            Database.insert(cv, AccessLevel.SYSTEM_MODE);
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE];
            Integer nextOrder = [
                SELECT COUNT() FROM Signature_Document__c WHERE Request__c = :requestId WITH SYSTEM_MODE
            ] + 1;
            Database.insert(
                new Signature_Document__c(
                    Request__c = requestId,
                    File_Name__c = fileName,
                    Content_Document_Id__c = cv.ContentDocumentId,
                    Content_Hash__c = DigitalSignatureService.sha256Hex(body),
                    Sort_Order__c = nextOrder
                ),
                AccessLevel.SYSTEM_MODE
            );
            DigitalSignatureService.refreshCounts(requestId);
            return payload(DigitalSignatureService.requireRequest(requestId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> addSigner(
        Id requestId,
        String fullName,
        String email,
        String mobile,
        String role,
        Decimal signingOrder
    ) {
        try {
            Signature_Request__c request = DigitalSignatureService.requireRequest(requestId);
            if (request.Status__c != DigitalSignatureService.STATUS_DRAFT) {
                throw handled('Signers can be added only while the request is a draft.');
            }
            if (String.isBlank(fullName)) {
                throw handled('Enter the signer’s legal name as it should appear on the pack.');
            }
            if (!String.isBlank(email) && !Pattern.matches('^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$', email)) {
                throw handled('Enter a valid email address for the signer.');
            }
            if (String.isBlank(mobile) || mobile.replaceAll('[^0-9]', '').length() < 10) {
                throw handled('Enter a 10-digit mobile number for OTP handover.');
            }
            Set<String> roles = new Set<String>{
                'Applicant', 'Co-Applicant', 'Guarantor', 'Authorised Signatory', 'Bank Officer'
            };
            String roleValue = roles.contains(role) ? role : 'Applicant';
            Decimal orderNo = signingOrder == null || signingOrder < 1 ? 1 : signingOrder;
            Database.insert(
                new Signature_Signer__c(
                    Request__c = requestId,
                    Full_Name__c = fullName.trim(),
                    Email__c = email,
                    Mobile__c = mobile,
                    Role__c = roleValue,
                    Signing_Order__c = orderNo,
                    Status__c = 'Pending'
                ),
                AccessLevel.SYSTEM_MODE
            );
            DigitalSignatureService.refreshCounts(requestId);
            return payload(DigitalSignatureService.requireRequest(requestId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> sendRequest(Id requestId) {
        try {
            Signature_Request__c request = DigitalSignatureService.requireRequest(requestId);
            if (request.Status__c != DigitalSignatureService.STATUS_DRAFT) {
                throw handled('This request has already been sent.');
            }
            List<Signature_Document__c> docs = [
                SELECT Id FROM Signature_Document__c WHERE Request__c = :requestId WITH SYSTEM_MODE
            ];
            List<Signature_Signer__c> signers = [
                SELECT Id, Status__c, Access_Code__c
                FROM Signature_Signer__c
                WHERE Request__c = :requestId
                WITH SYSTEM_MODE
                ORDER BY Signing_Order__c
            ];
            if (docs.isEmpty()) {
                throw handled('Attach at least one document before sending.');
            }
            if (signers.isEmpty()) {
                throw handled('Add at least one signer before sending.');
            }
            for (Signature_Signer__c signer : signers) {
                signer.Access_Code__c = DigitalSignatureService.generateAccessCode();
                signer.Status__c = 'Pending';
            }
            Database.update(signers, AccessLevel.SYSTEM_MODE);
            request.Status__c = DigitalSignatureService.STATUS_SENT;
            request.Sent_At__c = System.now();
            Database.update(request, AccessLevel.SYSTEM_MODE);
            DigitalSignatureService.refreshCounts(requestId);
            DigitalSignatureService.writeEvent(
                requestId,
                null,
                'Sent',
                DigitalSignatureService.combinedDocumentHash(requestId),
                null,
                'Request sent to ' + signers.size() + ' signer(s).'
            );
            return payload(DigitalSignatureService.requireRequest(requestId));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> revealOtp(Id signerId) {
        try {
            if (signerId == null) {
                throw handled('Signer is required.');
            }
            Signature_Signer__c signer = [
                SELECT Id, Request__c, Full_Name__c, Status__c
                FROM Signature_Signer__c
                WHERE Id = :signerId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            Signature_Request__c request = DigitalSignatureService.requireRequest(signer.Request__c);
            if (DigitalSignatureService.isExpired(request)) {
                DigitalSignatureService.markExpired(request);
                throw handled('This request has expired.');
            }
            if (signer.Status__c == 'Signed' || signer.Status__c == 'Declined') {
                throw handled('This signer has already finished.');
            }
            String otp = DigitalSignatureService.generateOtp();
            signer.Otp_Hash__c = DigitalSignatureService.hashOtp(signer.Id, otp);
            signer.Otp_Expires_At__c = System.now().addMinutes(15);
            signer.Status__c = 'OTP Sent';
            Database.update(signer, AccessLevel.SYSTEM_MODE);
            DigitalSignatureService.writeEvent(request.Id, signer.Id, 'OTP Issued', null, null, signer.Full_Name__c);
            Map<String, Object> result = payload(DigitalSignatureService.requireRequest(request.Id));
            result.put('otp', otp);
            result.put('signerId', signer.Id);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<Map<String, Object>> loadQueue() {
        try {
            List<Signature_Request__c> rows = [
                SELECT Id, Name, Title__c, Product_Type__c, Branch_Code__c, Status__c,
                       Expires_On__c, Sent_At__c, Completed_At__c, Document_Count__c,
                       Signer_Count__c, Signed_Count__c
                FROM Signature_Request__c
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 80
            ];
            return toMapList(rows);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> loadForSigner(String accessCode) {
        try {
            Signature_Signer__c signer = findSigner(accessCode);
            Signature_Request__c request = DigitalSignatureService.requireRequest(signer.Request__c);
            if (DigitalSignatureService.isExpired(request)) {
                DigitalSignatureService.markExpired(request);
                throw handled('This signature request has expired.');
            }
            if (signer.Status__c == 'Pending' || signer.Status__c == 'OTP Sent') {
                signer.Status__c = 'Viewed';
                Database.update(signer, AccessLevel.SYSTEM_MODE);
                if (request.Status__c == DigitalSignatureService.STATUS_SENT) {
                    request.Status__c = DigitalSignatureService.STATUS_IN_PROGRESS;
                    Database.update(request, AccessLevel.SYSTEM_MODE);
                }
                DigitalSignatureService.writeEvent(request.Id, signer.Id, 'Viewed', null, null, signer.Full_Name__c);
                request = DigitalSignatureService.requireRequest(request.Id);
            }
            Map<String, Object> result = payload(request);
            result.put('signer', toMap([
                SELECT Id, Full_Name__c, Email__c, Mobile__c, Role__c, Signing_Order__c, Status__c,
                       Access_Code__c, Signed_At__c, Signature_Type__c, Consent_Accepted__c
                FROM Signature_Signer__c
                WHERE Id = :signer.Id
                WITH SYSTEM_MODE
            ][0]));
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> sign(
        String accessCode,
        String otp,
        String signatureType,
        String signatureImage,
        Boolean consentAccepted
    ) {
        try {
            Signature_Signer__c signer = findSigner(accessCode);
            Signature_Request__c request = DigitalSignatureService.requireRequest(signer.Request__c);
            assertCanAct(request, signer, otp);
            if (consentAccepted != true) {
                throw handled('Accept the declaration before signing.');
            }
            if (String.isBlank(signatureImage)) {
                throw handled('Draw or type a signature.');
            }
            Signature_Signer__c nextSigner = DigitalSignatureService.nextPendingSigner(request.Id);
            if (nextSigner != null && nextSigner.Id != signer.Id) {
                throw handled('It is not this signer’s turn. Wait for ' + nextSigner.Full_Name__c + '.');
            }
            String packHash = DigitalSignatureService.combinedDocumentHash(request.Id);
            String signatureHash = DigitalSignatureService.sha256Hex(
                signer.Id + '|' + packHash + '|' + signatureImage + '|' + String.valueOf(System.now())
            );
            signer.Status__c = 'Signed';
            signer.Signed_At__c = System.now();
            signer.Signature_Type__c = String.isBlank(signatureType) ? 'Drawn' : signatureType;
            signer.Signature_Image__c = signatureImage.left(32768);
            signer.Consent_Accepted__c = true;
            Database.update(signer, AccessLevel.SYSTEM_MODE);
            DigitalSignatureService.writeEvent(request.Id, signer.Id, 'Signed', packHash, signatureHash, signer.Full_Name__c);
            DigitalSignatureService.refreshCounts(request.Id);
            Integer remaining = [
                SELECT COUNT()
                FROM Signature_Signer__c
                WHERE Request__c = :request.Id AND Status__c != 'Signed'
                WITH SYSTEM_MODE
            ];
            if (remaining == 0) {
                request.Status__c = DigitalSignatureService.STATUS_COMPLETED;
                request.Completed_At__c = System.now();
                Database.update(request, AccessLevel.SYSTEM_MODE);
            } else if (request.Status__c == DigitalSignatureService.STATUS_SENT) {
                request.Status__c = DigitalSignatureService.STATUS_IN_PROGRESS;
                Database.update(request, AccessLevel.SYSTEM_MODE);
            }
            Map<String, Object> result = payload(DigitalSignatureService.requireRequest(request.Id));
            result.put('signatureHash', signatureHash);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> decline(String accessCode, String otp, String reason) {
        try {
            Signature_Signer__c signer = findSigner(accessCode);
            Signature_Request__c request = DigitalSignatureService.requireRequest(signer.Request__c);
            assertCanAct(request, signer, otp);
            signer.Status__c = 'Declined';
            Database.update(signer, AccessLevel.SYSTEM_MODE);
            request.Status__c = DigitalSignatureService.STATUS_DECLINED;
            Database.update(request, AccessLevel.SYSTEM_MODE);
            DigitalSignatureService.writeEvent(
                request.Id,
                signer.Id,
                'Declined',
                DigitalSignatureService.combinedDocumentHash(request.Id),
                null,
                String.isBlank(reason) ? signer.Full_Name__c : reason
            );
            DigitalSignatureService.refreshCounts(request.Id);
            return payload(DigitalSignatureService.requireRequest(request.Id));
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    static Signature_Signer__c findSigner(String accessCode) {
        if (String.isBlank(accessCode)) {
            throw handled('Enter the access code.');
        }
        List<Signature_Signer__c> rows = [
            SELECT Id, Request__c, Full_Name__c, Status__c, Otp_Hash__c, Otp_Expires_At__c, Signing_Order__c
            FROM Signature_Signer__c
            WHERE Access_Code__c = :accessCode.trim().toUpperCase()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw handled('Access code was not found.');
        }
        return rows[0];
    }

    static void assertCanAct(Signature_Request__c request, Signature_Signer__c signer, String otp) {
        if (DigitalSignatureService.isExpired(request)) {
            DigitalSignatureService.markExpired(request);
            throw handled('This signature request has expired.');
        }
        if (signer.Status__c == 'Signed') {
            throw handled('This signer has already signed.');
        }
        if (signer.Status__c == 'Declined') {
            throw handled('This signer has already declined.');
        }
        if (String.isBlank(signer.Otp_Hash__c)) {
            throw handled('Ask the bank officer to reveal an OTP first.');
        }
        if (signer.Otp_Expires_At__c != null && signer.Otp_Expires_At__c < System.now()) {
            throw handled('The OTP has expired. Ask the officer to reveal a new one.');
        }
        String hashed = DigitalSignatureService.hashOtp(signer.Id, otp);
        if (hashed != signer.Otp_Hash__c) {
            DigitalSignatureService.writeEvent(request.Id, signer.Id, 'OTP Failed', null, null, signer.Full_Name__c);
            throw handled('The OTP is incorrect.');
        }
    }
}