/**
 * ERP AI use cases for the EngageIQ developer org.
 * Uses Einstein Models API when licensed, otherwise built-in financial AI.
 */
public with sharing class ERPAiService {
    public class InsightDTO {
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public String severity;
        @AuraEnabled public String actionKey;
        @AuraEnabled public String actionLabel;
    }

    public class ResultDTO {
        @AuraEnabled public String useCase;
        @AuraEnabled public String text;
        @AuraEnabled public String source;
        @AuraEnabled public Decimal score;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public List<InsightDTO> insights;
        @AuraEnabled public List<Map<String, Object>> lineSuggestions;
        @AuraEnabled public Map<String, Object> fields;
    }

    @AuraEnabled
    public static ResultDTO run(String useCase, String payloadJson) {
        Map<String, Object> payload = String.isBlank(payloadJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        String key = String.isBlank(useCase) ? 'dashboard' : useCase;
        ResultDTO result;
        if (key == 'dashboard') {
            result = dashboard(payload);
        } else if (key == 'itemSalesDescription') {
            result = itemDescription(payload, true);
        } else if (key == 'itemPurchaseDescription') {
            result = itemDescription(payload, false);
        } else if (key == 'itemSku') {
            result = itemSku(payload);
        } else if (key == 'customerCredit') {
            result = customerCredit(payload);
        } else if (key == 'documentSubject') {
            result = documentCopy(payload, 'subject');
        } else if (key == 'documentNotes') {
            result = documentCopy(payload, 'notes');
        } else if (key == 'documentTerms') {
            result = documentCopy(payload, 'terms');
        } else if (key == 'documentEmail') {
            result = documentCopy(payload, 'email');
        } else if (key == 'documentReview') {
            result = documentReview(payload);
        } else if (key == 'suggestLines') {
            result = suggestLines(payload);
        } else if (key == 'walkthroughTranslate') {
            result = walkthroughTranslate(payload);
        } else {
            throw new AuraHandledException('Unknown AI use case.');
        }
        result.useCase = key;
        if (String.isBlank(result.source)) {
            result.source = 'Built-in ERP AI';
        }
        return result;
    }

    public static List<InsightDTO> bootstrapInsights() {
        return dashboard(new Map<String, Object>()).insights;
    }

    public static String bootstrapSource() {
        return einsteinReady() ? 'Einstein GPT' : 'Built-in ERP AI';
    }

    static ResultDTO dashboard(Map<String, Object> payload) {
        Integer itemCount = count('ERP_Item__c');
        Integer customerCount = count('ERP_Customer__c');
        Integer draftItems = countWhere('ERP_Item__c', 'Status__c = \'Draft\'');
        Integer draftDocs = countWhere('ERP_Document__c', 'Status__c = \'Draft\'');
        Integer sentInvoices = countWhere('ERP_Document__c', 'Document_Type__c = \'Invoice\' AND Status__c = \'Sent\'');
        Integer missingGstin = countWhere('ERP_Customer__c', 'GSTIN__c = null');
        Decimal invoiceTotal = sumTotals('Invoice');
        Decimal quoteTotal = sumTotals('Quote');

        List<InsightDTO> insights = new List<InsightDTO>();
        if (itemCount == 0) {
            insights.add(insight('Catalogue is empty', 'Add catalogue rows so commercial offers and tax invoices can pick rates.', 'info', 'items', 'Add catalogue row'));
        } else if (draftItems > 0) {
            insights.add(insight(draftItems + ' working copy row(s)', 'Finish working copies so outward documents can use catalogue prices.', 'warn', 'items', 'Open Catalogue'));
        }
        if (customerCount == 0) {
            insights.add(insight('No clients yet', 'Register a client before you issue a commercial offer or tax invoice.', 'info', 'customers', 'Register a client'));
        } else if (missingGstin > 0) {
            insights.add(insight(missingGstin + ' client(s) missing GSTIN', 'Indian tax invoices usually need a GSTIN. Upload a PAN or GST scan to fill it.', 'warn', 'customers', 'Open Client Register'));
        }
        if (sentInvoices == 0) {
            insights.add(insight('No tax invoices issued', 'Collections start after the first tax invoice is issued.', 'info', 'invoices', 'Raise tax invoice'));
        } else {
            insights.add(insight('Money owed to you', 'Issued tax invoices total ' + money(invoiceTotal) + '. Follow overdue balances from Command Center.', 'ok', 'invoices', 'Open Tax Invoices'));
        }
        if (quoteTotal > invoiceTotal && quoteTotal > 0) {
            insights.add(insight('Offers ahead of tax invoices', 'Open commercial offers total ' + money(quoteTotal) + '. Raise a tax invoice when the client accepts.', 'warn', 'quotes', 'Open Commercial Offers'));
        }
        if (draftDocs > 0) {
            insights.add(insight(draftDocs + ' working copy document(s)', 'Keep a working copy while you edit, then issue it when ready.', 'info', 'quotes', 'Review working copies'));
        }
        if (insights.isEmpty()) {
            insights.add(insight('Levarus Salesforce ERP is ready', 'Catalogue, clients, and documents look healthy. Use AI for copy and a credit check.', 'ok', 'home', null));
        }

        ResultDTO result = baseResult(joinInsights(insights));
        result.insights = insights;
        result.fields = new Map<String, Object>{
            'itemCount' => itemCount,
            'customerCount' => customerCount,
            'invoiceTotal' => invoiceTotal
        };
        return withEinstein(result, 'Summarize this ERP dashboard for a finance user in 3 short bullets:\n' + result.text);
    }

    static ResultDTO itemDescription(Map<String, Object> payload, Boolean sales) {
        String name = text(payload.get('name'));
        String itemType = defaultText(payload.get('itemType'), 'Goods');
        String unit = defaultText(payload.get('unit'), 'pcs');
        Decimal selling = toDecimal(payload.get('sellingPrice'));
        Decimal cost = toDecimal(payload.get('costPrice'));
        String vendor = text(payload.get('preferredVendor'));
        String prompt = sales
            ? 'Write a 2-sentence sales catalog description for Indian SME invoicing. Item: ' + name + ', type: ' + itemType + ', unit: ' + unit + ', selling price INR ' + selling + '. No emojis.'
            : 'Write a 2-sentence purchase description for procurement. Item: ' + name + ', type: ' + itemType + ', cost INR ' + cost + ', vendor: ' + vendor + '. No emojis.';
        String fallback = sales
            ? (blank(name) ? 'Add an item name, then generate a sales description.' :
                name + ' is offered as ' + itemType.toLowerCase() + ' and billed per ' + unit +
                (selling == null ? '.' : ' at INR ' + selling.setScale(2) + '.') +
                ' Include this line on quotes and invoices so the customer sees the commercial intent clearly.')
            : (blank(name) ? 'Add an item name, then generate a purchase description.' :
                'Procure ' + name + ' as ' + itemType.toLowerCase() +
                (cost == null ? '.' : ' at an estimated cost of INR ' + cost.setScale(2) + '.') +
                (blank(vendor) ? ' Confirm the preferred vendor before raising a bill.' : ' Preferred vendor: ' + vendor + '.'));
        ResultDTO result = baseResult(fallback);
        result.fields = new Map<String, Object>{
            (sales ? 'salesDescription' : 'purchaseDescription') => fallback
        };
        return withEinstein(result, prompt);
    }

    static ResultDTO itemSku(Map<String, Object> payload) {
        String name = text(payload.get('name'));
        String itemType = defaultText(payload.get('itemType'), 'Goods');
        String sku = suggestSku(name, itemType);
        ResultDTO result = baseResult(sku);
        result.fields = new Map<String, Object>{ 'sku' => sku };
        return withEinstein(result, 'Suggest one compact SKU code (max 12 chars, letters and numbers only) for item ' + name + ' type ' + itemType + '. Return only the SKU.');
    }

    static ResultDTO customerCredit(Map<String, Object> payload) {
        String displayName = defaultText(payload.get('displayName'), 'this customer');
        String customerType = defaultText(payload.get('customerType'), 'Business');
        String gstin = text(payload.get('gstin'));
        String pan = text(payload.get('pan'));
        String emailAddress = text(payload.get('emailAddress'));
        String paymentTerms = defaultText(payload.get('paymentTerms'), 'Due on Receipt');
        Decimal opening = toDecimal(payload.get('openingBalance'));
        List<String> warnings = new List<String>();
        Decimal score = 78;
        if (blank(gstin)) {
            score -= 12;
            warnings.add('GSTIN is missing. Add it before GST invoices.');
        } else if (!Pattern.matches('^[0-9A-Z]{15}$', gstin.toUpperCase())) {
            score -= 8;
            warnings.add('GSTIN should be 15 letters/numbers.');
        }
        if (blank(pan)) {
            score -= 6;
            warnings.add('PAN is not captured.');
        } else if (!Pattern.matches('^[A-Z]{5}[0-9]{4}[A-Z]$', pan.toUpperCase())) {
            score -= 5;
            warnings.add('PAN format looks invalid.');
        }
        if (blank(emailAddress)) {
            score -= 8;
            warnings.add('Email is missing, so Send will not have a delivery address.');
        }
        if (opening != null && opening < 0) {
            score -= 10;
            warnings.add('Opening balance is negative. Confirm credit exposure.');
        }
        if (paymentTerms.contains('60') || paymentTerms.contains('45')) {
            score -= 6;
            warnings.add('Long payment terms increase collection risk.');
        }
        if (score < 40) {
            score = 40;
        }
        String notes =
            'AI credit review for ' + displayName + ' (' + customerType + ').\n' +
            'Suggested terms: ' + paymentTerms + '.\n' +
            (warnings.isEmpty() ? 'Master data looks complete enough to transact.' : String.join(warnings, '\n'));
        ResultDTO result = baseResult(notes);
        result.score = score.setScale(2);
        result.warnings = warnings;
        result.fields = new Map<String, Object>{
            'remarks' => notes,
            'aiCreditScore' => result.score,
            'aiCreditNotes' => notes
        };
        return withEinstein(
            result,
            'Write a short credit-control note for Indian SME customer ' + displayName +
                '. Type ' + customerType + ', GSTIN ' + gstin + ', PAN ' + pan +
                ', opening ' + opening + ', terms ' + paymentTerms +
                '. Include a 0-100 score first. No emojis.'
        );
    }

    static ResultDTO documentCopy(Map<String, Object> payload, String kind) {
        String docType = defaultText(payload.get('documentType'), 'Quote');
        String customerName = defaultText(payload.get('customerName'), 'Customer');
        String subjectHint = text(payload.get('subject'));
        String numberValue = defaultText(payload.get('documentNumber'), docType);
        Decimal totalAmount = toDecimal(payload.get('totalAmount'));
        String fallback;
        String prompt;
        if (kind == 'subject') {
            fallback = blank(subjectHint)
                ? docType + ' for ' + customerName + (totalAmount == null ? '' : ' — ' + money(totalAmount))
                : subjectHint;
            prompt = 'Write one short subject line for a ' + docType + ' to ' + customerName + '. Return only the subject.';
        } else if (kind == 'notes') {
            fallback = 'Thank you for your business, ' + customerName +
                '. Please review this ' + docType.toLowerCase() +
                ' and write to us if any line or tax treatment needs a change.';
            prompt = 'Write 2 polite customer notes for an Indian ' + docType + ' to ' + customerName + '. No emojis.';
        } else if (kind == 'terms') {
            fallback =
                '1. Payment is due as per the stated payment terms.\n' +
                '2. GST, TDS, and TCS will be applied as required under Indian law.\n' +
                '3. Goods remain our property until payment is received in full.\n' +
                '4. Disputes must be raised within 7 days of the document date.';
            prompt = 'Write 4 concise terms and conditions for an Indian SME ' + docType + '. Numbered list only.';
        } else {
            fallback =
                'Dear ' + customerName + ',\n\n' +
                'Please find ' + docType.toLowerCase() + ' ' + numberValue +
                (totalAmount == null ? '' : ' for ' + money(totalAmount)) +
                '.\n\nYou can reply to this email with any change needed.\n\nRegards,\nAccounts';
            prompt = 'Write a short professional email sending ' + docType + ' ' + numberValue +
                ' to ' + customerName + ' totaling ' + totalAmount + ' INR. No emojis.';
        }
        ResultDTO result = baseResult(fallback);
        String fieldName = kind == 'subject' ? 'subject' : kind == 'notes' ? 'customerNotes' : kind == 'terms' ? 'termsConditions' : 'aiEmailDraft';
        result.fields = new Map<String, Object>{ fieldName => fallback };
        ResultDTO generated = withEinstein(result, prompt);
        if (generated.fields == null) {
            generated.fields = new Map<String, Object>();
        }
        generated.fields.put(fieldName, generated.text);
        return generated;
    }

    static ResultDTO documentReview(Map<String, Object> payload) {
        String customerName = text(payload.get('customerName'));
        Decimal discount = toDecimal(payload.get('discountPercent'));
        Decimal totalAmount = toDecimal(payload.get('totalAmount'));
        List<String> warnings = new List<String>();
        if (blank(customerName)) {
            warnings.add('Customer is missing.');
        }
        if (discount != null && discount >= 20) {
            warnings.add('Discount is ' + discount.setScale(2) + '%. Confirm approval before send.');
        }
        if (totalAmount == null || totalAmount <= 0) {
            warnings.add('Total is zero. Add line items before send.');
        }
        List<Object> lines = payload.get('lineItems') instanceof List<Object>
            ? (List<Object>) payload.get('lineItems')
            : new List<Object>();
        if (lines.isEmpty()) {
            warnings.add('No item rows captured.');
        }
        String summary = warnings.isEmpty()
            ? 'AI review looks clear to send. Totals and customer are present.'
            : 'AI review flags:\n' + String.join(warnings, '\n');
        ResultDTO result = baseResult(summary);
        result.warnings = warnings;
        result.fields = new Map<String, Object>{ 'aiSummary' => summary };
        return withEinstein(result, 'Review this sales document for risk in 3 bullets: ' + JSON.serialize(payload).left(4000));
    }

    static ResultDTO suggestLines(Map<String, Object> payload) {
        List<Map<String, Object>> suggestions = new List<Map<String, Object>>();
        for (ERP_Item__c rec : [
            SELECT Name, Selling_Price__c, Unit__c, Sales_Description__c, Status__c
            FROM ERP_Item__c
            WHERE Sales_Enabled__c = true AND Status__c = 'Active'
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 5
        ]) {
            suggestions.add(new Map<String, Object>{
                'details' => rec.Name,
                'qty' => 1,
                'rate' => rec.Selling_Price__c == null ? 0 : rec.Selling_Price__c,
                'notes' => rec.Sales_Description__c
            });
        }
        ResultDTO result = baseResult(suggestions.isEmpty()
            ? 'No active sales items yet. Create an item first.'
            : 'Suggested ' + suggestions.size() + ' catalog item(s).');
        result.lineSuggestions = suggestions;
        return result;
    }

    static ResultDTO walkthroughTranslate(Map<String, Object> payload) {
        String languageName = defaultText(payload.get('languageName'), 'English');
        String languageCode = defaultText(payload.get('languageCode'), 'en-IN');
        String scenesJson = defaultText(payload.get('scenesJson'), '[]');
        ResultDTO result = baseResult(scenesJson);
        String prompt =
            'Translate this Levarus Salesforce ERP product walkthrough into ' +
            languageName +
            ' (' +
            languageCode +
            '). Keep the same JSON array length and keys: title, caption, mock, voice. ' +
            'Return JSON only, no markdown. Source JSON:\n' +
            scenesJson.left(8000);
        return withEinstein(result, prompt);
    }

    static ResultDTO withEinstein(ResultDTO fallback, String prompt) {
        String generated = ERPEinsteinLlm.generate(prompt);
        if (String.isBlank(generated)) {
            fallback.source = 'Built-in ERP AI';
            return fallback;
        }
        fallback.text = generated;
        fallback.source = 'Einstein GPT';
        if (fallback.fields != null) {
            for (String key : fallback.fields.keySet()) {
                if (fallback.fields.get(key) instanceof String && key != 'sku') {
                    fallback.fields.put(key, generated);
                }
            }
            if (fallback.fields.containsKey('sku')) {
                fallback.fields.put('sku', firstToken(generated));
                fallback.text = firstToken(generated);
            }
            if (fallback.fields.containsKey('aiCreditScore')) {
                Decimal parsed = parseScore(generated);
                if (parsed != null) {
                    fallback.score = parsed;
                    fallback.fields.put('aiCreditScore', parsed);
                }
            }
        }
        return fallback;
    }

    static ResultDTO baseResult(String text) {
        ResultDTO result = new ResultDTO();
        result.text = text;
        result.insights = new List<InsightDTO>();
        result.warnings = new List<String>();
        result.lineSuggestions = new List<Map<String, Object>>();
        result.fields = new Map<String, Object>();
        return result;
    }

    static InsightDTO insight(String title, String detail, String severity, String actionKey, String actionLabel) {
        InsightDTO row = new InsightDTO();
        row.title = title;
        row.detail = detail;
        row.severity = severity;
        row.actionKey = actionKey;
        row.actionLabel = actionLabel;
        return row;
    }

    static Boolean einsteinReady() {
        List<AI_Integration__mdt> rows = [
            SELECT Enabled__c
            FROM AI_Integration__mdt
            WHERE DeveloperName = 'ERP_Generative'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return !rows.isEmpty() && rows[0].Enabled__c == true;
    }

    static Integer count(String objectApi) {
        return Database.countQuery('SELECT COUNT() FROM ' + objectApi, AccessLevel.SYSTEM_MODE);
    }

    static Integer countWhere(String objectApi, String whereClause) {
        return Database.countQuery('SELECT COUNT() FROM ' + objectApi + ' WHERE ' + whereClause, AccessLevel.SYSTEM_MODE);
    }

    static Decimal sumTotals(String documentType) {
        Decimal total = 0;
        for (AggregateResult row : [
            SELECT SUM(Total__c) amt
            FROM ERP_Document__c
            WHERE Document_Type__c = :documentType
            WITH SYSTEM_MODE
        ]) {
            total = (Decimal) row.get('amt');
        }
        return total == null ? 0 : total;
    }

    static String suggestSku(String name, String itemType) {
        String prefix = itemType == 'Service' ? 'SRV' : 'GDS';
        String compact = blank(name) ? 'ITEM' : name.replaceAll('[^A-Za-z0-9]', '').toUpperCase();
        if (compact.length() > 6) {
            compact = compact.substring(0, 6);
        }
        Integer salt = Math.mod(Math.abs((prefix + compact).hashCode()), 900) + 100;
        return (prefix + '-' + compact + salt).left(16);
    }

    static String joinInsights(List<InsightDTO> insights) {
        List<String> lines = new List<String>();
        for (InsightDTO row : insights) {
            lines.add(row.title + ': ' + row.detail);
        }
        return String.join(lines, '\n');
    }

    static String money(Decimal value) {
        Decimal amount = value == null ? 0 : value;
        return '₹' + String.valueOf(amount.setScale(2));
    }

    static String text(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    static String defaultText(Object value, String fallback) {
        String raw = text(value);
        return String.isBlank(raw) ? fallback : raw;
    }

    static Boolean blank(String value) {
        return String.isBlank(value);
    }

    static Decimal toDecimal(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    static String firstToken(String value) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.replaceAll('[^A-Za-z0-9\\-]', ' ').trim().split('\\s+')[0].toUpperCase().left(16);
    }

    static Decimal parseScore(String value) {
        Matcher matcher = Pattern.compile('(\\d{2,3}(?:\\.\\d+)?)').matcher(value == null ? '' : value);
        if (matcher.find()) {
            Decimal parsed = Decimal.valueOf(matcher.group(1));
            if (parsed > 100) {
                parsed = 100;
            }
            return parsed;
        }
        return null;
    }
}