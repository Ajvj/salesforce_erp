public with sharing class OcrService {
    public class Result {
        public Boolean configured;
        public Boolean success;
        public String status;
        public String extractedText;
        public String rawJson;
        public String extractedName;
        public String extractedFirstName;
        public String extractedLastName;
        public String extractedGender;
        public String extractedPlaceOfBirth;
        public String extractedStreet;
        public String extractedCity;
        public String extractedState;
        public String extractedPostal;
        public String extractedId;
        public String extractedPan;
        public String extractedGstin;
        public String extractedFatherName;
        public String extractedMotherName;
        public Date extractedExpiry;
        public Date extractedDob;
        public String message;
    }

    @TestVisible
    static AI_Integration__mdt testConfig;

    public static AI_Integration__mdt config() {
        if (testConfig != null) {
            return testConfig;
        }
        List<AI_Integration__mdt> rows = [
            SELECT Enabled__c, Endpoint__c, Bearer_Token__c, Model_Id__c
            FROM AI_Integration__mdt
            WHERE DeveloperName = 'Einstein_OCR'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Boolean isConfigured() {
        AI_Integration__mdt cfg = config();
        return cfg != null &&
            cfg.Enabled__c == true &&
            String.isNotBlank(cfg.Bearer_Token__c) &&
            String.isNotBlank(cfg.Endpoint__c);
    }

    public static Result extract(Blob fileBody, String fileName) {
        return extract(fileBody, fileName, null);
    }

    public static Result extract(Blob fileBody, String fileName, String existingBase64) {
        Result res = new Result();
        String localText = readableLocalText(fileBody, fileName);
        res.extractedText = localText;
        applyHeuristics(res);

        Boolean runRemote = isConfigured() && (testConfig != null || !Test.isRunningTest());
        if (runRemote && fileBody != null && fileBody.size() > 600 * 1024) {
            runRemote = false;
            res.message = 'The scan is larger than 600 KB, so image OCR was skipped. Local document AI was used.';
        }
        if (runRemote) {
            res.configured = true;
            try {
                Result remote = callRemote(fileBody, fileName, existingBase64);
                res.rawJson = remote.rawJson;
                if (remote.success && String.isNotBlank(remote.extractedText)) {
                    res.extractedText = (remote.extractedText + '\n' + localText).left(32000);
                    applyHeuristics(res);
                    res.success = true;
                    res.status = 'Complete';
                    res.message = 'Document OCR read the file and document AI mapped KYC fields.';
                    return res;
                }
                res.message = String.isBlank(remote.message)
                    ? 'Document OCR did not return text. Local document AI was used.'
                    : remote.message + ' Local document AI was used.';
            } catch (Exception e) {
                res.message = 'Document OCR failed: ' + e.getMessage() + '. Local document AI was used.';
            }
        } else if (String.isBlank(res.message)) {
            res.configured = isConfigured();
            res.message =
                'Document AI mapped fields from the file name and readable text. ' +
                'Image OCR is enabled when AI Integration → Einstein OCR has Enabled and a token.';
        }

        res.success = true;
        res.status = 'Complete';
        return res;
    }

    static Result callRemote(Blob fileBody, String fileName, String existingBase64) {
        AI_Integration__mdt cfg = config();
        if (cfg != null && String.isNotBlank(cfg.Endpoint__c) && cfg.Endpoint__c.containsIgnoreCase('ocr.space')) {
            return callOcrSpace(fileBody, fileName, existingBase64);
        }
        return callEinstein(fileBody, fileName);
    }

    static Result callOcrSpace(Blob fileBody, String fileName, String existingBase64) {
        Result res = new Result();
        AI_Integration__mdt cfg = config();
        String b64 = String.isBlank(existingBase64) ? EncodingUtil.base64Encode(fileBody) : existingBase64.replace(' ', '+');
        if (b64.length() > 550000 || (fileBody != null && fileBody.size() > 400 * 1024)) {
            res.success = false;
            res.message = 'The scan is stored. Image OCR was skipped because the file is large; fields were mapped from readable text.';
            return res;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Endpoint__c);
        req.setMethod('POST');
        req.setTimeout(60000);
        req.setHeader('apikey', cfg.Bearer_Token__c.trim());
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'base64Image=data:' + mimeForFile(fileName) + ';base64,' + b64.replace('+', '%2B') +
            '&language=eng&isOverlayRequired=false&OCREngine=2&scale=true&detectOrientation=true'
        );
        HttpResponse httpRes = new Http().send(req);
        res.rawJson = String.valueOf(httpRes.getBody()).left(8000);
        if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300) {
            res.extractedText = parseText(httpRes.getBody());
            res.success = String.isNotBlank(res.extractedText);
            if (!res.success) {
                res.message = 'OCR completed but no text was detected in the image.';
            }
        } else {
            res.success = false;
            res.message = 'OCR HTTP ' + httpRes.getStatusCode() + ': ' + String.valueOf(httpRes.getBody()).left(500);
        }
        return res;
    }

    static String mimeForFile(String fileName) {
        String lower = fileName == null ? '' : fileName.toLowerCase();
        if (lower.endsWith('.pdf')) {
            return 'application/pdf';
        }
        if (lower.endsWith('.png')) {
            return 'image/png';
        }
        if (lower.endsWith('.gif')) {
            return 'image/gif';
        }
        if (lower.endsWith('.tif') || lower.endsWith('.tiff')) {
            return 'image/tiff';
        }
        return 'image/jpeg';
    }

    static Result callEinstein(Blob fileBody, String fileName) {
        Result res = new Result();
        AI_Integration__mdt cfg = config();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Endpoint__c);
        req.setMethod('POST');
        req.setTimeout(120000);
        req.setHeader('Authorization', 'Bearer ' + cfg.Bearer_Token__c.trim());
        req.setHeader('Cache-Control', 'no-cache');

        String boundary = '----ocr' + String.valueOf(Crypto.getRandomInteger());
        String modelId = String.isBlank(cfg.Model_Id__c) ? 'OCRModel' : cfg.Model_Id__c;
        String bodyStart =
            '--' + boundary + '\r\n' +
            'Content-Disposition: form-data; name="modelId"\r\n\r\n' +
            modelId + '\r\n' +
            '--' + boundary + '\r\n' +
            'Content-Disposition: form-data; name="sampleContent"; filename="' +
            (String.isBlank(fileName) ? 'document.png' : fileName.replace('"', '')) +
            '"\r\n' +
            'Content-Type: application/octet-stream\r\n\r\n';
        String bodyEnd = '\r\n--' + boundary + '--';
        req.setHeader('Content-Type', 'multipart/form-data; boundary=' + boundary);
        req.setBodyAsBlob(
            EncodingUtil.convertFromHex(
                EncodingUtil.convertToHex(Blob.valueOf(bodyStart)) +
                EncodingUtil.convertToHex(fileBody) +
                EncodingUtil.convertToHex(Blob.valueOf(bodyEnd))
            )
        );

        HttpResponse httpRes = new Http().send(req);
        res.rawJson = httpRes.getBody();
        if (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300) {
            res.success = true;
            res.extractedText = parseText(httpRes.getBody());
        } else {
            res.success = false;
            res.message = 'OCR HTTP ' + httpRes.getStatusCode() + ': ' + String.valueOf(httpRes.getBody()).left(500);
        }
        return res;
    }

    static String printableText(Blob fileBody) {
        if (fileBody == null) {
            return '';
        }
        try {
            return fileBody.toString();
        } catch (Exception e) {
            return '';
        }
    }

    static String readableLocalText(Blob fileBody, String fileName) {
        String name = fileName == null ? '' : fileName;
        String bodyText = printableText(fileBody);
        if (!isReadableDocumentText(bodyText)) {
            return name;
        }
        return (name + '\n' + bodyText).left(32000);
    }

    static Boolean isReadableDocumentText(String text) {
        if (String.isBlank(text) || text.length() < 8) {
            return false;
        }
        Integer letters = text.replaceAll('[^A-Za-z]', '').length();
        return letters >= 20 && (Decimal.valueOf(letters) / Decimal.valueOf(text.length()) * 100) >= 25;
    }

    @TestVisible
    static String parseText(String jsonBody) {
        if (String.isBlank(jsonBody)) {
            return '';
        }
        List<String> lines = new List<String>();
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
            Object parsed = root.get('ParsedResults');
            if (parsed instanceof List<Object>) {
                for (Object row : (List<Object>) parsed) {
                    if (row instanceof Map<String, Object>) {
                        Object text = ((Map<String, Object>) row).get('ParsedText');
                        if (text != null) {
                            lines.add(String.valueOf(text));
                        }
                    }
                }
            }
            Object probs = root.get('probabilities');
            if (probs instanceof List<Object>) {
                for (Object row : (List<Object>) probs) {
                    if (row instanceof Map<String, Object>) {
                        Object label = ((Map<String, Object>) row).get('label');
                        if (label != null) {
                            lines.add(String.valueOf(label));
                        }
                    }
                }
            }
        } catch (Exception e) {
            return jsonBody.left(32000);
        }
        return String.join(lines, '\n');
    }

    @TestVisible
    static void applyHeuristics(Result res) {
        if (res == null || String.isBlank(res.extractedText)) {
            return;
        }
        res.extractedName = null;
        res.extractedFirstName = null;
        res.extractedLastName = null;
        res.extractedGender = null;
        res.extractedPlaceOfBirth = null;
        res.extractedStreet = null;
        res.extractedCity = null;
        res.extractedState = null;
        res.extractedPostal = null;
        res.extractedId = null;
        res.extractedPan = null;
        res.extractedGstin = null;
        res.extractedFatherName = null;
        res.extractedMotherName = null;
        res.extractedExpiry = null;
        res.extractedDob = null;

        String text = res.extractedText;
        parseMrz(res, text);

        String surname = labeledName(text, new List<String>{
            'surname', 'family name', 'last name', 'nom'
        });
        String given = labeledName(text, new List<String>{
            'given names', 'given name(s)', 'given name', 'first name', 'prenoms', 'prenom', 'forenames', 'forename'
        });
        if (isUsableName(surname)) {
            res.extractedLastName = titleCase(cleanName(surname));
        }
        if (isUsableName(given)) {
            res.extractedFirstName = titleCase(cleanName(given));
        }
        if (String.isBlank(res.extractedFirstName) || String.isBlank(res.extractedLastName)) {
            String combined = labeledName(text, new List<String>{ 'full name', 'name of holder' });
            if (isUsableName(combined)) {
                List<String> parts = titleCase(cleanName(combined)).split('\\s+');
                if (String.isBlank(res.extractedFirstName) && !parts.isEmpty()) {
                    res.extractedFirstName = parts[0];
                }
                if (String.isBlank(res.extractedLastName) && parts.size() > 1) {
                    res.extractedLastName = parts[parts.size() - 1];
                }
            }
        }
        if (String.isNotBlank(res.extractedFirstName) || String.isNotBlank(res.extractedLastName)) {
            res.extractedName = ((res.extractedFirstName == null ? '' : res.extractedFirstName) +
                ' ' +
                (res.extractedLastName == null ? '' : res.extractedLastName)).trim();
        }

        String gender = labeledValue(text, new List<String>{ 'gender', 'sex', 'sexe' });
        res.extractedGender = normalizeGender(gender);

        String pob = labeledValue(text, new List<String>{ 'place of birth', 'lieu de naissance', 'birth place' });
        if (String.isNotBlank(pob) && !pob.replaceAll('[0-9./-]', '').trim().equals('')) {
            res.extractedPlaceOfBirth = titleCase(pob).left(80);
        }

        res.extractedFatherName = labeledName(text, new List<String>{
            'name of father', 'father\'s name', 'fathers name', 'legal guardian'
        });
        res.extractedMotherName = labeledName(text, new List<String>{
            'name of mother', 'mother\'s name', 'mothers name', 'mother maiden'
        });

        String compact = text.replaceAll('[\\r\\n]+', ' ');
        Matcher passportNo = Pattern.compile('(?i)\\b([A-Z]{1,2}[0-9]{6,8})\\b').matcher(compact);
        if (passportNo.find() && !Pattern.compile('^[A-Z]{5}[0-9]{4}[A-Z]$').matcher(passportNo.group(1).toUpperCase()).matches()) {
            res.extractedId = passportNo.group(1).toUpperCase();
        }
        Matcher pan = Pattern.compile('(?i)\\b([A-Z]{5}[0-9]{4}[A-Z])\\b').matcher(compact);
        if (pan.find()) {
            res.extractedPan = pan.group(1).toUpperCase();
            if (String.isBlank(res.extractedId)) {
                res.extractedId = res.extractedPan;
            }
        }
        Matcher gstin = Pattern.compile('(?i)\\b([0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9])\\b').matcher(compact);
        if (gstin.find()) {
            res.extractedGstin = gstin.group(1).toUpperCase();
            if (String.isBlank(res.extractedPan) && res.extractedGstin.length() >= 12) {
                res.extractedPan = res.extractedGstin.substring(2, 12);
            }
        }
        String legal = labeledName(text, new List<String>{
            'legal name', 'legal name of business', 'trade name', 'name of the taxable person'
        });
        if (isUsableName(legal) && String.isBlank(res.extractedName)) {
            res.extractedName = titleCase(cleanName(legal));
        }
        Matcher idMatch = Pattern.compile('(?i)\\b(?:passport|id|document)\\s*(?:no|number|#)?[:\\s]+([A-Z0-9]{6,18})\\b').matcher(compact);
        if (idMatch.find() && String.isBlank(res.extractedId)) {
            res.extractedId = idMatch.group(1);
        }

        String dobRaw = labeledValue(text, new List<String>{
            'date of birth', 'date de naissance', 'birth date', 'dob'
        });
        Date parsedDob = asDateOfBirth(parseFlexibleDate(dobRaw));
        if (parsedDob == null) {
            Matcher dob = Pattern.compile('(?i)(?:date of birth|dob)[:\\s]+([0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{2,4})').matcher(compact);
            if (dob.find()) {
                parsedDob = asDateOfBirth(parseFlexibleDate(dob.group(1)));
            }
        }
        if (parsedDob != null) {
            res.extractedDob = parsedDob;
        }

        String expRaw = labeledValue(text, new List<String>{
            'date of expiry', 'date of expity', 'date of expiration', 'expiry date', 'expires'
        });
        res.extractedExpiry = parseFlexibleDate(expRaw);
        if (res.extractedExpiry == null) {
            Matcher exp = Pattern.compile('(?i)(?:date of exp(?:iry|ity|iration)?|expiry|expires)[:\\s]+([0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{2,4})').matcher(compact);
            if (exp.find()) {
                res.extractedExpiry = parseFlexibleDate(exp.group(1));
            }
        }
        parseAddress(res, text);
        if (String.isBlank(res.extractedPostal) || String.isBlank(res.extractedStreet)) {
            parsePinBlock(res, text);
        }
    }

    static void parseMrz(Result res, String text) {
        for (String line : normalizeLines(text)) {
            String compact = line.replaceAll('[^A-Z0-9<]', '').toUpperCase();
            Matcher mrz = Pattern.compile('P[<K][A-Z]{3}([A-Z<]+)<<([A-Z<]+)').matcher(compact);
            if (mrz.find()) {
                String surname = mrz.group(1).replace('<', ' ').trim();
                String given = mrz.group(2).replace('<', ' ').trim();
                if (String.isBlank(res.extractedLastName) && isUsableName(surname)) {
                    res.extractedLastName = titleCase(surname);
                }
                if (String.isBlank(res.extractedFirstName) && isUsableName(given)) {
                    res.extractedFirstName = titleCase(given);
                }
            }
            Matcher mrzDob = Pattern.compile('([0-9]{6})[0-9]?[MFX]([0-9]{6})').matcher(compact);
            if (mrzDob.find()) {
                Date dob = parseMrzDate(mrzDob.group(1), false);
                Date expiry = parseMrzDate(mrzDob.group(2), true);
                if (res.extractedDob == null && dob != null) {
                    res.extractedDob = dob;
                }
                if (res.extractedExpiry == null && expiry != null) {
                    res.extractedExpiry = expiry;
                }
            }
        }
    }

    static Date parseMrzDate(String yymmdd, Boolean asExpiry) {
        if (String.isBlank(yymmdd) || yymmdd.length() != 6) {
            return null;
        }
        try {
            Integer yy = Integer.valueOf(yymmdd.substring(0, 2));
            Integer mm = Integer.valueOf(yymmdd.substring(2, 4));
            Integer dd = Integer.valueOf(yymmdd.substring(4, 6));
            if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
                return null;
            }
            Date from2000 = Date.newInstance(2000 + yy, mm, dd);
            Date from1900 = Date.newInstance(1900 + yy, mm, dd);
            if (asExpiry == true) {
                return from2000 < Date.today().addYears(-15) ? Date.newInstance(2100 + yy, mm, dd) : from2000;
            }
            if (from2000 > Date.today() || from2000 < Date.today().addYears(-120)) {
                return from1900;
            }
            return from2000;
        } catch (Exception e) {
            return null;
        }
    }

    static Date asDateOfBirth(Date value) {
        if (value == null || value > Date.today() || value < Date.today().addYears(-120)) {
            return null;
        }
        return value;
    }

    static void parseAddress(Result res, String text) {
        String block = labeledBlock(text, new List<String>{
            'permanent address', 'address of holder', 'residential address', 'place of residence', 'address'
        });
        if (String.isBlank(block)) {
            parsePinBlock(res, text);
            return;
        }
        Matcher pin = Pattern.compile('\\b([1-9][0-9]{5})\\b').matcher(block);
        if (pin.find()) {
            res.extractedPostal = pin.group(1);
        } else {
            Matcher zip = Pattern.compile('\\b([0-9]{5}(?:-[0-9]{4})?)\\b').matcher(block);
            if (zip.find()) {
                res.extractedPostal = zip.group(1);
            }
        }
        String cleaned = block;
        if (String.isNotBlank(res.extractedPostal)) {
            cleaned = cleaned.replace(res.extractedPostal, ' ');
        }
        String stateFound = matchIndianState(cleaned);
        if (String.isNotBlank(stateFound)) {
            res.extractedState = titleCase(stateFound);
            cleaned = cleaned.replaceAll('(?i)' + stateFound, ' ');
        }
        List<String> lines = new List<String>();
        for (String line : cleaned.split('\\n')) {
            String trimmed = line.replaceAll('\\s+', ' ').trim();
            if (String.isNotBlank(trimmed) && !looksLikeLabel(trimmed)) {
                lines.add(trimmed);
            }
        }
        if (!lines.isEmpty()) {
            res.extractedStreet = titleCase(lines[0]).left(255);
        }
        if (lines.size() > 1) {
            res.extractedCity = titleCase(lines[1]).left(80);
        } else if (!lines.isEmpty()) {
            List<String> streetParts = lines[0].split(',');
            if (streetParts.size() > 1) {
                res.extractedCity = titleCase(streetParts[streetParts.size() - 1].trim()).left(80);
            }
        }
    }

    static void parsePinBlock(Result res, String text) {
        List<String> lines = normalizeLines(text);
        for (Integer i = 0; i < lines.size(); i++) {
            Matcher pin = Pattern.compile('(?i)(?:PIN|Pincode|Pin code)[:\\s]*([1-9][0-9]{5})').matcher(lines[i]);
            if (!pin.find()) {
                continue;
            }
            if (String.isBlank(res.extractedPostal)) {
                res.extractedPostal = pin.group(1);
            }
            String state = matchIndianState(lines[i] + ' ' + (i > 0 ? lines[i - 1] : ''));
            if (String.isNotBlank(state) && String.isBlank(res.extractedState)) {
                res.extractedState = titleCase(state);
            }
            String areaLine = i > 0 ? lines[i - 1] : '';
            String streetLine = i > 1 ? lines[i - 2] : '';
            if (!looksLikeStreet(streetLine) && looksLikeStreet(areaLine)) {
                streetLine = areaLine;
                areaLine = '';
            }
            List<String> areaParts = areaLine.split(',');
            if (areaParts.size() >= 2) {
                if (String.isBlank(res.extractedCity)) {
                    res.extractedCity = titleCase(areaParts[1].trim()).left(80);
                }
                String area = areaParts[0].trim();
                if (String.isNotBlank(streetLine)) {
                    streetLine = streetLine + ', ' + area;
                } else {
                    streetLine = area;
                }
            } else if (String.isNotBlank(areaLine) && String.isBlank(res.extractedCity) && !looksLikeStreet(areaLine)) {
                res.extractedCity = titleCase(areaLine).left(80);
            }
            if (String.isNotBlank(streetLine) && String.isBlank(res.extractedStreet)) {
                res.extractedStreet = titleCase(streetLine).left(255);
            }
            return;
        }
    }

    static Boolean looksLikeStreet(String value) {
        if (String.isBlank(value) || looksLikeLabel(value)) {
            return false;
        }
        String upper = value.toUpperCase();
        return value.replaceAll('[0-9]', '') != value ||
            upper.contains('NO ') ||
            upper.contains('PLOT') ||
            upper.contains('FLAT') ||
            upper.contains('STREET') ||
            upper.contains('ROAD') ||
            upper.contains('PHASE');
    }

    static String matchIndianState(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        String upper = text.toUpperCase();
        List<String> states = new List<String>{
            'ANDHRA PRADESH', 'ARUNACHAL PRADESH', 'HIMACHAL PRADESH', 'MADHYA PRADESH',
            'UTTAR PRADESH', 'WEST BENGAL', 'TAMIL NADU', 'TAMILNADU', 'KARNATAKA',
            'MAHARASHTRA', 'TELANGANA', 'KERALA', 'GUJARAT', 'RAJASTHAN', 'ODISHA',
            'JHARKHAND', 'CHHATTISGARH', 'UTTARAKHAND', 'PUNJAB', 'HARYANA', 'BIHAR',
            'ASSAM', 'DELHI', 'GOA', 'MANIPUR', 'MEGHALAYA', 'MIZORAM', 'NAGALAND',
            'SIKKIM', 'TRIPURA', 'LADAKH', 'PUDUCHERRY'
        };
        for (String state : states) {
            if (upper.contains(state)) {
                return state == 'TAMILNADU' ? 'TAMIL NADU' : state;
            }
        }
        return null;
    }

    static String labeledName(String text, List<String> labels) {
        List<String> lines = normalizeLines(text);
        for (Integer i = 0; i < lines.size(); i++) {
            String line = stripBilingual(lines[i]).trim();
            String upper = line.toUpperCase();
            for (String label : labels) {
                String lab = label.toUpperCase();
                Integer idx = upper.indexOf(lab);
                if (idx < 0 || idx > 24) {
                    continue;
                }
                String rest = stripBilingual(line.substring(idx + lab.length())).trim();
                rest = rest.replaceFirst('^[:.\\s()/\\-]+', '').trim();
                if (isUsableName(rest)) {
                    return titleCase(cleanName(rest));
                }
                Integer taken = 0;
                for (Integer j = i + 1; j < lines.size() && taken < 3; j++) {
                    String next = stripBilingual(lines[j]).trim();
                    if (String.isBlank(next)) {
                        continue;
                    }
                    if (looksLikeLabel(next) && !isUsableName(next)) {
                        break;
                    }
                    taken++;
                    if (isUsableName(next)) {
                        return titleCase(cleanName(next));
                    }
                }
            }
        }
        return null;
    }

    static String labeledValue(String text, List<String> labels) {
        List<String> lines = normalizeLines(text);
        for (Integer i = 0; i < lines.size(); i++) {
            String line = stripBilingual(lines[i]).trim();
            String upper = line.toUpperCase();
            for (String label : labels) {
                String lab = label.toUpperCase();
                Integer idx = upper.indexOf(lab);
                if (idx < 0 || idx > 18) {
                    continue;
                }
                if (lab.length() <= 4 && idx > 0) {
                    continue;
                }
                String rest = stripBilingual(line.substring(idx + lab.length())).trim();
                rest = rest.replaceFirst('^[:.\\s()/\\-]+', '').trim();
                if (isPlausibleValue(rest)) {
                    return rest;
                }
                if (i + 1 < lines.size()) {
                    String next = stripBilingual(lines[i + 1]).trim();
                    if (isPlausibleValue(next) && !looksLikeLabel(next)) {
                        return next;
                    }
                }
            }
        }
        return null;
    }

    static String labeledBlock(String text, List<String> labels) {
        List<String> lines = normalizeLines(text);
        for (Integer i = 0; i < lines.size(); i++) {
            String line = stripBilingual(lines[i]).trim();
            String upper = line.toUpperCase();
            for (String label : labels) {
                String lab = label.toUpperCase();
                Integer idx = upper.indexOf(lab);
                if (idx < 0 || idx > 18) {
                    continue;
                }
                List<String> block = new List<String>();
                String rest = stripBilingual(line.substring(idx + lab.length())).trim().replaceFirst('^[:.\\s()/\\-]+', '').trim();
                if (isPlausibleValue(rest) && !looksLikeLabel(rest)) {
                    block.add(rest);
                }
                Integer taken = 0;
                for (Integer j = i + 1; j < lines.size() && taken < 4; j++) {
                    String next = stripBilingual(lines[j]).trim();
                    if (String.isBlank(next)) {
                        continue;
                    }
                    if (looksLikeLabel(next) || next.toUpperCase().startsWith('P<')) {
                        break;
                    }
                    block.add(next);
                    taken++;
                }
                if (!block.isEmpty()) {
                    return String.join(block, '\n');
                }
            }
        }
        return null;
    }

    static List<String> normalizeLines(String text) {
        List<String> out = new List<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String line : text.replace('\r', '\n').split('\\n')) {
            String trimmed = line.replaceAll('\\s+', ' ').trim();
            if (String.isNotBlank(trimmed)) {
                out.add(trimmed);
            }
        }
        return out;
    }

    static String stripBilingual(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        Matcher english = Pattern.compile(
            '(?i)/\\s*(Surname|Given Names?|Given Name\\(s\\)|First Name|Last Name|Date of Birth|Place of Birth|' +
            'Date of Issue|Date of Expir\\w*|Date of Expity|Nationality|Sex|Gender|Address|' +
            'Name of Father|Name of Mother|Name of Spouse|Father\'s Name|Passport No|Type|Code)'
        ).matcher(value);
        if (english.find()) {
            return (english.group(1) + value.substring(english.end())).replaceAll('\\s+', ' ').trim();
        }
        return value.replaceAll('(?i)/\\s*(Nom|Prenoms?|Sexe|Nom de famille)[A-Za-z ]*', ' ')
            .replaceAll('\\s+', ' ')
            .trim();
    }

    static Boolean isPlausibleValue(String value) {
        return String.isNotBlank(value) && value.length() >= 1 && value.length() <= 120 && !looksLikeLabel(value);
    }

    static Boolean looksLikeLabel(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String upper = value.toUpperCase().replaceAll('[^A-Z ]', ' ').replaceAll('\\s+', ' ').trim();
        Set<String> labels = new Set<String>{
            'SURNAME', 'GIVEN NAME', 'GIVEN NAMES', 'GIVEN NAME S', 'FIRST NAME', 'LAST NAME',
            'DATE OF BIRTH', 'PLACE OF BIRTH', 'DATE OF EXPIRY', 'DATE OF ISSUE',
            'NATIONALITY', 'SEX', 'GENDER', 'ADDRESS', 'PASSPORT', 'TYPE', 'CODE',
            'COUNTRY CODE', 'PASSPORT NO', 'PASSPORT NUMBER', 'DATE OF EXPITY',
            'NAME OF FATHER', 'NAME OF MOTHER', 'NAME OF SPOUSE', 'LEGAL GUARDIAN',
            'FATHERS NAME', 'MOTHERS NAME', 'PERMANENT ACCOUNT NUMBER CARD',
            'INCOME TAX DEPARTMENT', 'GOVT OF INDIA'
        };
        return labels.contains(upper);
    }

    static Boolean isUsableName(String value) {
        if (String.isBlank(value) || value.length() < 2) {
            return false;
        }
        if (value.replaceAll('[0-9]', '') != value) {
            return false;
        }
        String letters = value.replaceAll('[^A-Za-z]', '');
        if (letters.length() < 2) {
            return false;
        }
        String upper = value.toUpperCase().replaceAll('[^A-Z ]', '').trim();
        Set<String> noise = new Set<String>{
            'PASSPORT', 'REPUBLIC', 'INDIA', 'INDIAN', 'AMERICA', 'UNITED', 'STATES',
            'GOVERNMENT', 'OFFICIAL', 'SPECIMEN', 'NATIONALITY', 'TYPE', 'CODE',
            'MALE', 'FEMALE', 'OTHER', 'IND', 'LEGAL GUARDIAN', 'FATHER', 'MOTHER',
            'SPOUSE', 'NAME', 'GIVEN NAME', 'GIVEN NAMES'
        };
        return !noise.contains(upper);
    }

    static String cleanName(String value) {
        return value == null ? null : value.replaceAll('[^A-Za-z .\\-]', ' ').replaceAll('\\s+', ' ').trim();
    }

    static String titleCase(String raw) {
        if (String.isBlank(raw)) {
            return raw;
        }
        List<String> out = new List<String>();
        for (String word : raw.toLowerCase().split('\\s+')) {
            if (String.isBlank(word)) {
                continue;
            }
            out.add(word.substring(0, 1).toUpperCase() + (word.length() > 1 ? word.substring(1) : ''));
        }
        return String.join(out, ' ');
    }

    static String normalizeGender(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String v = raw.trim().toUpperCase();
        if (v == 'M' || v.startsWith('MALE') || v == 'H' || v.startsWith('HOMME')) {
            return 'Male';
        }
        if (v == 'F' || v.startsWith('FEMALE') || v == 'W' || v.startsWith('FEMME')) {
            return 'Female';
        }
        if (v == 'X' || v.startsWith('OTHER')) {
            return 'Other';
        }
        return null;
    }

    static Date parseFlexibleDate(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        Matcher iso = Pattern.compile('([0-9]{4})[./-]([0-9]{1,2})[./-]([0-9]{1,2})').matcher(raw);
        if (iso.find()) {
            try {
                return Date.newInstance(
                    Integer.valueOf(iso.group(1)),
                    Integer.valueOf(iso.group(2)),
                    Integer.valueOf(iso.group(3))
                );
            } catch (Exception e) {
                return null;
            }
        }
        Matcher numeric = Pattern.compile('([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{2,4})').matcher(raw);
        if (numeric.find()) {
            return dateFromParts(numeric.group(1), numeric.group(2), numeric.group(3));
        }
        Matcher named = Pattern.compile('([0-9]{1,2})\\s*([A-Za-z]{3,9})\\s*([0-9]{2,4})').matcher(raw);
        if (named.find()) {
            Integer month = monthFromName(named.group(2));
            if (month != null) {
                try {
                    Integer day = Integer.valueOf(named.group(1));
                    Integer year = Integer.valueOf(named.group(3));
                    if (year < 100) {
                        year = year > 30 ? 1900 + year : 2000 + year;
                    }
                    return Date.newInstance(year, month, day);
                } catch (Exception e) {
                    return null;
                }
            }
        }
        return null;
    }

    static Date dateFromParts(String aRaw, String bRaw, String cRaw) {
        try {
            Integer a = Integer.valueOf(aRaw);
            Integer b = Integer.valueOf(bRaw);
            Integer c = Integer.valueOf(cRaw);
            if (c < 100) {
                c = c > 30 ? 1900 + c : 2000 + c;
            }
            if (a > 12) {
                return Date.newInstance(c, b, a);
            }
            if (b > 12) {
                return Date.newInstance(c, a, b);
            }
            return Date.newInstance(c, b, a);
        } catch (Exception e) {
            return null;
        }
    }

    static Integer monthFromName(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String key = raw.trim().toUpperCase().left(3);
        Map<String, Integer> months = new Map<String, Integer>{
            'JAN' => 1, 'FEB' => 2, 'MAR' => 3, 'APR' => 4, 'MAY' => 5, 'JUN' => 6,
            'JUL' => 7, 'AUG' => 8, 'SEP' => 9, 'OCT' => 10, 'NOV' => 11, 'DEC' => 12
        };
        return months.get(key);
    }
}