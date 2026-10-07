/**
 * ERP catalog for the EngageIQ developer org.
 * Internal users get App Launcher access via ERP Access; Community Plus users get object/Apex access.
 */
public with sharing class ERPController {
    public class ItemDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String itemType;
        @AuraEnabled public String unit;
        @AuraEnabled public String category;
        @AuraEnabled public String sku;
        @AuraEnabled public Decimal sellingPrice;
        @AuraEnabled public String salesAccount;
        @AuraEnabled public String salesDescription;
        @AuraEnabled public Decimal costPrice;
        @AuraEnabled public String purchaseAccount;
        @AuraEnabled public String purchaseDescription;
        @AuraEnabled public String taxCode;
        @AuraEnabled public String preferredVendor;
        @AuraEnabled public Boolean trackInventory;
        @AuraEnabled public Boolean salesEnabled;
        @AuraEnabled public Boolean purchaseEnabled;
        @AuraEnabled public String status;
        @AuraEnabled public String lastModified;
    }

    public class CustomerDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String displayName;
        @AuraEnabled public String customerType;
        @AuraEnabled public String salutation;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String companyName;
        @AuraEnabled public String emailAddress;
        @AuraEnabled public String workPhone;
        @AuraEnabled public String mobile;
        @AuraEnabled public String customerLanguage;
        @AuraEnabled public String pan;
        @AuraEnabled public String gstin;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String accountsReceivable;
        @AuraEnabled public String accountsPayable;
        @AuraEnabled public Decimal openingBalance;
        @AuraEnabled public String paymentTerms;
        @AuraEnabled public Boolean portalAccess;
        @AuraEnabled public String billingAddress;
        @AuraEnabled public String shippingAddress;
        @AuraEnabled public String billingAttention;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String billingStreet1;
        @AuraEnabled public String billingStreet2;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPin;
        @AuraEnabled public String billingPhone;
        @AuraEnabled public String billingFax;
        @AuraEnabled public String shippingAttention;
        @AuraEnabled public String shippingCountry;
        @AuraEnabled public String shippingStreet1;
        @AuraEnabled public String shippingStreet2;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingPin;
        @AuraEnabled public String shippingPhone;
        @AuraEnabled public String shippingFax;
        @AuraEnabled public String contactPersons;
        @AuraEnabled public String customFields;
        @AuraEnabled public String reportingTags;
        @AuraEnabled public String remarks;
        @AuraEnabled public String status;
        @AuraEnabled public String lastModified;
    }

    public class DashboardDTO {
        @AuraEnabled public Decimal totalReceivables;
        @AuraEnabled public Decimal currentReceivables;
        @AuraEnabled public Decimal overdueReceivables;
        @AuraEnabled public Decimal totalPayables;
        @AuraEnabled public Decimal currentPayables;
        @AuraEnabled public Decimal overduePayables;
        @AuraEnabled public Decimal totalIncome;
        @AuraEnabled public Decimal totalExpenses;
        @AuraEnabled public Integer itemCount;
        @AuraEnabled public Integer draftCount;
        @AuraEnabled public Integer activeCount;
        @AuraEnabled public Integer customerCount;
    }

    public class DocumentDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String documentType;
        @AuraEnabled public String documentNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String docDate;
        @AuraEnabled public String expiryDate;
        @AuraEnabled public String expectedShipmentDate;
        @AuraEnabled public String dueDate;
        @AuraEnabled public String salesperson;
        @AuraEnabled public String projectName;
        @AuraEnabled public String subject;
        @AuraEnabled public String paymentTerms;
        @AuraEnabled public String deliveryMethod;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String accountsReceivable;
        @AuraEnabled public String lineItemsJson;
        @AuraEnabled public Decimal subTotal;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Decimal taxAmount;
        @AuraEnabled public Decimal adjustment;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public String taxType;
        @AuraEnabled public String taxName;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public String customerNotes;
        @AuraEnabled public String termsConditions;
        @AuraEnabled public String attachmentName;
        @AuraEnabled public String discountLevel;
        @AuraEnabled public Boolean giveDiscounts;
        @AuraEnabled public Boolean addAdjustments;
        @AuraEnabled public Boolean addShipping;
        @AuraEnabled public String rounding;
        @AuraEnabled public Boolean taxForSubscriptions;
        @AuraEnabled public String status;
        @AuraEnabled public String lastModified;
    }

    public class BootstrapDTO {
        @AuraEnabled public List<ItemDTO> items;
        @AuraEnabled public List<CustomerDTO> customers;
        @AuraEnabled public List<DocumentDTO> documents;
        @AuraEnabled public DashboardDTO dashboard;
        @AuraEnabled public List<String> units;
        @AuraEnabled public List<String> salesAccounts;
        @AuraEnabled public List<String> purchaseAccounts;
        @AuraEnabled public List<String> vendors;
        @AuraEnabled public List<String> displayNames;
        @AuraEnabled public List<String> receivableAccounts;
        @AuraEnabled public List<String> paymentTerms;
        @AuraEnabled public String aiSource;
        @AuraEnabled public List<ERPAiService.InsightDTO> insights;
        @AuraEnabled public ERPBooksController.BooksDTO books;
    }

    public class IdentityScanDTO {
        @AuraEnabled public String pan;
        @AuraEnabled public String gstin;
        @AuraEnabled public String displayName;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String companyName;
        @AuraEnabled public String billingStreet1;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPin;
        @AuraEnabled public String message;
        @AuraEnabled public String extractedText;
    }

    @AuraEnabled
    public static BootstrapDTO getBootstrap() {
        try {
            ERPSampleData.ensure();
        } catch (Exception e) {
            // Load whatever records exist if seed is blocked.
        }
        BootstrapDTO data = new BootstrapDTO();
        data.items = listItems();
        data.customers = listCustomers();
        data.documents = listDocuments();
        data.dashboard = buildDashboard(data.items, data.customers, data.documents);
        data.units = distinctItemValues('Unit__c');
        data.salesAccounts = distinctItemValues('Sales_Account__c');
        data.purchaseAccounts = distinctItemValues('Purchase_Account__c');
        data.vendors = distinctItemValues('Preferred_Vendor__c');
        data.displayNames = distinctCustomerValues('Name');
        data.receivableAccounts = distinctCustomerValues('Accounts_Receivable__c');
        data.paymentTerms = distinctCustomerValues('Payment_Terms__c');
        data.aiSource = ERPAiService.bootstrapSource();
        data.insights = ERPAiService.bootstrapInsights();
        try {
            data.books = ERPBooksController.getBooks();
        } catch (Exception e) {
            data.books = new ERPBooksController.BooksDTO();
        }
        return data;
    }

    @AuraEnabled
    public static IdentityScanDTO readIdentityScan(String fileName, String base64Data) {
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('Upload a PAN or GSTIN scan first.');
        }
        Blob body;
        try {
            body = EncodingUtil.base64Decode(base64Data.replace(' ', '+'));
        } catch (Exception e) {
            throw new AuraHandledException('The file could not be read. Try a JPG, PNG, or PDF.');
        }
        OcrService.Result ocr = OcrService.extract(body, fileName);
        IdentityScanDTO dto = new IdentityScanDTO();
        dto.pan = ocr.extractedPan;
        dto.gstin = ocr.extractedGstin;
        dto.firstName = ocr.extractedFirstName;
        dto.lastName = ocr.extractedLastName;
        dto.displayName = ocr.extractedName;
        dto.companyName = ocr.extractedName;
        dto.billingStreet1 = ocr.extractedStreet;
        dto.billingCity = ocr.extractedCity;
        dto.billingState = ocr.extractedState;
        dto.billingPin = ocr.extractedPostal;
        dto.extractedText = ocr.extractedText;
        dto.message = ocr.message;
        if (String.isBlank(dto.gstin) && String.isBlank(dto.pan)) {
            dto.message = String.isBlank(dto.message)
                ? 'No PAN or GSTIN was read. Try a clearer scan.'
                : dto.message;
        } else if (String.isBlank(dto.message)) {
            List<String> parts = new List<String>();
            if (String.isNotBlank(dto.gstin)) {
                parts.add('GSTIN ' + dto.gstin);
            }
            if (String.isNotBlank(dto.pan)) {
                parts.add('PAN ' + dto.pan);
            }
            dto.message = 'Read ' + String.join(parts, ' and ') + ' from the upload.';
        }
        return dto;
    }

    @AuraEnabled
    public static ERPAiService.ResultDTO runAi(String useCase, String payloadJson) {
        return ERPAiService.run(useCase, payloadJson);
    }

    @AuraEnabled
    public static List<ItemDTO> listItems() {
        List<ItemDTO> rows = new List<ItemDTO>();
        for (ERP_Item__c rec : [
            SELECT Id, Name, Type__c, Unit__c, SKU__c, Selling_Price__c, Sales_Account__c,
                   Sales_Description__c, Cost_Price__c, Purchase_Account__c, Purchase_Description__c,
                   Preferred_Vendor__c, Tax_Code__c, Track_Inventory__c, Sales_Enabled__c, Purchase_Enabled__c, Category__c,
                   Status__c, LastModifiedDate
            FROM ERP_Item__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            rows.add(toItemDto(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static List<CustomerDTO> listCustomers() {
        List<CustomerDTO> rows = new List<CustomerDTO>();
        for (ERP_Customer__c rec : [
            SELECT Id, Name, Customer_Type__c, Salutation__c, First_Name__c, Last_Name__c,
                   Company_Name__c, Email__c, Work_Phone__c, Mobile__c, Customer_Language__c,
                   PAN__c, GSTIN__c, Currency_Code__c, Accounts_Receivable__c, Accounts_Payable__c, Opening_Balance__c,
                   Payment_Terms__c, Portal_Access__c, Billing_Address__c, Shipping_Address__c,
                   Billing_Attention__c, Billing_Country__c, Billing_Street_1__c, Billing_Street_2__c,
                   Billing_City__c, Billing_State__c, Billing_Pin__c, Billing_Phone__c, Billing_Fax__c,
                   Shipping_Attention__c, Shipping_Country__c, Shipping_Street_1__c, Shipping_Street_2__c,
                   Shipping_City__c, Shipping_State__c, Shipping_Pin__c, Shipping_Phone__c, Shipping_Fax__c,
                   Contact_Persons__c, Custom_Fields__c, Reporting_Tags__c, Remarks__c,
                   Status__c, LastModifiedDate
            FROM ERP_Customer__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            rows.add(toCustomerDto(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static Id saveItem(String payloadJson, Boolean asDraft) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        Boolean draft = asDraft == true;
        String name = textValue(payload.get('name'));
        if (String.isBlank(name)) {
            name = draft ? 'Untitled Item' : null;
        }
        if (!draft && String.isBlank(name)) {
            throw new AuraHandledException('Name is required.');
        }

        Boolean salesEnabled = boolValue(payload.get('salesEnabled'), true);
        Boolean purchaseEnabled = boolValue(payload.get('purchaseEnabled'), true);

        if (!draft) {
            if (salesEnabled) {
                if (payload.get('sellingPrice') == null || String.isBlank(String.valueOf(payload.get('sellingPrice')))) {
                    throw new AuraHandledException('Selling Price is required.');
                }
                if (String.isBlank(textValue(payload.get('salesAccount')))) {
                    throw new AuraHandledException('Sales Account is required.');
                }
            }
            if (purchaseEnabled) {
                if (payload.get('costPrice') == null || String.isBlank(String.valueOf(payload.get('costPrice')))) {
                    throw new AuraHandledException('Cost Price is required.');
                }
                if (String.isBlank(textValue(payload.get('purchaseAccount')))) {
                    throw new AuraHandledException('Purchase Account is required.');
                }
            }
        }

        ERP_Item__c rec = new ERP_Item__c();
        String recordId = textValue(payload.get('id'));
        if (String.isNotBlank(recordId)) {
            rec.Id = recordId;
        }
        rec.Name = name;
        rec.Type__c = defaultText(textValue(payload.get('itemType')), 'Goods');
        rec.SKU__c = textValue(payload.get('sku'));
        applyUomAndCategory(rec, payload);
        rec.Selling_Price__c = decimalValue(payload.get('sellingPrice'));
        rec.Sales_Account__c = textValue(payload.get('salesAccount'));
        rec.Sales_Description__c = textValue(payload.get('salesDescription'));
        rec.Cost_Price__c = decimalValue(payload.get('costPrice'));
        rec.Purchase_Account__c = textValue(payload.get('purchaseAccount'));
        rec.Purchase_Description__c = textValue(payload.get('purchaseDescription'));
        rec.Tax_Code__c = textValue(payload.get('taxCode'));
        rec.Preferred_Vendor__c = textValue(payload.get('preferredVendor'));
        rec.Track_Inventory__c = boolValue(payload.get('trackInventory'), false);
        rec.Sales_Enabled__c = salesEnabled;
        rec.Purchase_Enabled__c = purchaseEnabled;
        rec.Status__c = draft ? 'Draft' : 'Active';
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveItemStock(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        String sku = textValue(payload.get('sku'));
        String name = textValue(payload.get('product'));
        if (String.isBlank(name)) {
            name = String.isBlank(sku) ? 'Untitled Item' : sku;
        }
        ERP_Item__c rec;
        if (String.isNotBlank(sku)) {
            List<ERP_Item__c> bySku = [SELECT Id FROM ERP_Item__c WHERE SKU__c = :sku WITH SYSTEM_MODE LIMIT 1];
            if (!bySku.isEmpty()) {
                rec = bySku[0];
            }
        }
        if (rec == null) {
            List<ERP_Item__c> byName = [SELECT Id FROM ERP_Item__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
            if (!byName.isEmpty()) {
                rec = byName[0];
            }
        }
        if (rec == null) {
            rec = new ERP_Item__c();
            rec.Name = name;
            rec.SKU__c = sku;
            rec.Type__c = 'Goods';
            rec.Status__c = 'Active';
            rec.Track_Inventory__c = true;
        }
        applyUomAndCategory(rec, payload);
        putText(rec, 'Warehouse__c', textValue(payload.get('warehouse')));
        putText(rec, 'Bin_Location__c', textValue(payload.get('binLocation')));
        putText(rec, 'Batch_Number__c', textValue(payload.get('batchNumber')));
        putText(rec, 'Serial_Number__c', textValue(payload.get('serialNumber')));
        rec.Stock_On_Hand__c = decimalValue(payload.get('onHand'));
        rec.Committed_Quantity__c = decimalValue(payload.get('committedQty'));
        rec.Available_Quantity__c = decimalValue(payload.get('availableQty'));
        rec.On_Order_Quantity__c = decimalValue(payload.get('onOrderQty'));
        rec.Reorder_Level__c = decimalValue(payload.get('reorderLevel'));
        rec.Inventory_Value__c = decimalValue(payload.get('value'));
        if (payload.get('unitCost') != null && String.isNotBlank(String.valueOf(payload.get('unitCost')))) {
            rec.Cost_Price__c = decimalValue(payload.get('unitCost'));
        }
        String stockStatus = textValue(payload.get('stockStatus'));
        rec.Stock_Status__c = String.isBlank(stockStatus) ? 'In stock' : stockStatus;
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveCustomer(String payloadJson, Boolean asDraft) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        Boolean draft = asDraft == true;
        String displayName = textValue(payload.get('displayName'));
        if (String.isBlank(displayName)) {
            displayName = draft ? 'Untitled Customer' : null;
        }
        if (!draft && String.isBlank(displayName)) {
            throw new AuraHandledException('Display Name is required.');
        }

        ERP_Customer__c rec = new ERP_Customer__c();
        String recordId = textValue(payload.get('id'));
        if (String.isNotBlank(recordId)) {
            rec.Id = recordId;
        }
        rec.Name = displayName;
        rec.Customer_Type__c = defaultText(textValue(payload.get('customerType')), 'Business');
        rec.Salutation__c = textValue(payload.get('salutation'));
        rec.First_Name__c = textValue(payload.get('firstName'));
        rec.Last_Name__c = textValue(payload.get('lastName'));
        rec.Company_Name__c = textValue(payload.get('companyName'));
        rec.Email__c = textValue(payload.get('emailAddress'));
        rec.Work_Phone__c = textValue(payload.get('workPhone'));
        rec.Mobile__c = textValue(payload.get('mobile'));
        rec.Customer_Language__c = defaultText(textValue(payload.get('customerLanguage')), 'English');
        rec.PAN__c = textValue(payload.get('pan'));
        rec.GSTIN__c = textValue(payload.get('gstin'));
        rec.Currency_Code__c = defaultText(textValue(payload.get('currencyCode')), 'INR- Indian Rupee');
        rec.Accounts_Receivable__c = textValue(payload.get('accountsReceivable'));
        rec.Accounts_Payable__c = textValue(payload.get('accountsPayable'));
        rec.Opening_Balance__c = decimalValue(payload.get('openingBalance'));
        rec.Payment_Terms__c = defaultText(textValue(payload.get('paymentTerms')), 'Due on Receipt');
        rec.Portal_Access__c = boolValue(payload.get('portalAccess'), false);
        rec.Billing_Address__c = textValue(payload.get('billingAddress'));
        rec.Shipping_Address__c = textValue(payload.get('shippingAddress'));
        rec.Billing_Attention__c = textValue(payload.get('billingAttention'));
        rec.Billing_Country__c = textValue(payload.get('billingCountry'));
        rec.Billing_Street_1__c = textValue(payload.get('billingStreet1'));
        rec.Billing_Street_2__c = textValue(payload.get('billingStreet2'));
        rec.Billing_City__c = textValue(payload.get('billingCity'));
        rec.Billing_State__c = textValue(payload.get('billingState'));
        rec.Billing_Pin__c = textValue(payload.get('billingPin'));
        rec.Billing_Phone__c = textValue(payload.get('billingPhone'));
        rec.Billing_Fax__c = textValue(payload.get('billingFax'));
        rec.Shipping_Attention__c = textValue(payload.get('shippingAttention'));
        rec.Shipping_Country__c = textValue(payload.get('shippingCountry'));
        rec.Shipping_Street_1__c = textValue(payload.get('shippingStreet1'));
        rec.Shipping_Street_2__c = textValue(payload.get('shippingStreet2'));
        rec.Shipping_City__c = textValue(payload.get('shippingCity'));
        rec.Shipping_State__c = textValue(payload.get('shippingState'));
        rec.Shipping_Pin__c = textValue(payload.get('shippingPin'));
        rec.Shipping_Phone__c = textValue(payload.get('shippingPhone'));
        rec.Shipping_Fax__c = textValue(payload.get('shippingFax'));
        rec.Contact_Persons__c = textValue(payload.get('contactPersons'));
        rec.Custom_Fields__c = textValue(payload.get('customFields'));
        rec.Reporting_Tags__c = textValue(payload.get('reportingTags'));
        rec.Remarks__c = textValue(payload.get('remarks'));
        rec.Status__c = draft ? 'Draft' : 'Active';
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static void deleteItem(Id itemId) {
        if (itemId == null) {
            throw new AuraHandledException('Item is required.');
        }
        Database.delete([SELECT Id FROM ERP_Item__c WHERE Id = :itemId WITH SYSTEM_MODE LIMIT 1], AccessLevel.SYSTEM_MODE);
    }

    @AuraEnabled
    public static void deleteCustomer(Id customerId) {
        if (customerId == null) {
            throw new AuraHandledException('Customer is required.');
        }
        Database.delete([SELECT Id FROM ERP_Customer__c WHERE Id = :customerId WITH SYSTEM_MODE LIMIT 1], AccessLevel.SYSTEM_MODE);
    }

    @AuraEnabled
    public static List<DocumentDTO> listDocuments() {
        List<DocumentDTO> rows = new List<DocumentDTO>();
        for (ERP_Document__c rec : [
            SELECT Id, Name, Document_Type__c, Customer_Name__c, Reference__c, Doc_Date__c, Expiry_Date__c,
                   Expected_Shipment_Date__c, Due_Date__c, Salesperson__c, Project_Name__c, Subject__c,
                   Payment_Terms__c, Delivery_Method__c, Order_Number__c, Accounts_Receivable__c,
                   Line_Items_JSON__c, Sub_Total__c, Discount_Percent__c, Tax_Amount__c, Adjustment__c,
                   Total__c, Tax_Type__c, Tax_Name__c, Currency__c, Customer_Notes__c, Terms_Conditions__c,
                   Attachment_Name__c, Discount_Level__c, Give_Discounts__c, Add_Adjustments__c,
                   Add_Shipping__c, Rounding__c, Tax_For_Subscriptions__c, Status__c, LastModifiedDate
            FROM ERP_Document__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            rows.add(toDocumentDto(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static Id saveDocument(String payloadJson, Boolean asDraft) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        Boolean draft = asDraft == true;
        String customerName = textValue(payload.get('customerName'));
        String documentType = defaultText(textValue(payload.get('documentType')), 'Quote');
        String documentNumber = textValue(payload.get('documentNumber'));
        if (!draft && String.isBlank(customerName)) {
            throw new AuraHandledException('Customer Name is required.');
        }
        if (String.isBlank(documentNumber)) {
            documentNumber = draft ? ('Draft-' + documentType) : documentType + '-00001';
        }
        if (String.isBlank(customerName)) {
            customerName = 'Untitled Customer';
        }

        String status = draft ? 'Draft' : defaultText(textValue(payload.get('status')), 'Sent');
        ERP_Document__c rec = new ERP_Document__c();
        String recordId = textValue(payload.get('id'));
        if (String.isNotBlank(recordId)) {
            rec.Id = recordId;
        }
        rec.Name = documentNumber;
        rec.Document_Type__c = documentType;
        rec.Customer_Name__c = customerName;
        rec.Reference__c = textValue(payload.get('referenceNumber'));
        rec.Doc_Date__c = dateValue(payload.get('docDate'));
        rec.Expiry_Date__c = dateValue(payload.get('expiryDate'));
        rec.Expected_Shipment_Date__c = dateValue(payload.get('expectedShipmentDate'));
        rec.Due_Date__c = dateValue(payload.get('dueDate'));
        rec.Salesperson__c = textValue(payload.get('salesperson'));
        rec.Project_Name__c = textValue(payload.get('projectName'));
        rec.Subject__c = textValue(payload.get('subject'));
        rec.Payment_Terms__c = textValue(payload.get('paymentTerms'));
        rec.Delivery_Method__c = textValue(payload.get('deliveryMethod'));
        rec.Order_Number__c = textValue(payload.get('orderNumber'));
        rec.Accounts_Receivable__c = textValue(payload.get('accountsReceivable'));
        rec.Line_Items_JSON__c = textValue(payload.get('lineItemsJson'));
        rec.Sub_Total__c = decimalValue(payload.get('subTotal'));
        rec.Discount_Percent__c = decimalValue(payload.get('discountPercent'));
        rec.Tax_Amount__c = decimalValue(payload.get('taxAmount'));
        rec.Adjustment__c = decimalValue(payload.get('adjustment'));
        rec.Total__c = decimalValue(payload.get('totalAmount'));
        rec.Tax_Type__c = textValue(payload.get('taxType'));
        rec.Tax_Name__c = textValue(payload.get('taxName'));
        rec.Currency__c = textValue(payload.get('currency'));
        rec.Customer_Notes__c = textValue(payload.get('customerNotes'));
        rec.Terms_Conditions__c = textValue(payload.get('termsConditions'));
        rec.Attachment_Name__c = textValue(payload.get('attachmentName'));
        rec.Discount_Level__c = textValue(payload.get('discountLevel'));
        rec.Give_Discounts__c = boolValue(payload.get('giveDiscounts'), true);
        rec.Add_Adjustments__c = boolValue(payload.get('addAdjustments'), true);
        rec.Add_Shipping__c = boolValue(payload.get('addShipping'), false);
        rec.Rounding__c = textValue(payload.get('rounding'));
        rec.Tax_For_Subscriptions__c = boolValue(payload.get('taxForSubscriptions'), true);
        rec.Status__c = status;
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static void deleteDocument(Id documentId) {
        if (documentId == null) {
            throw new AuraHandledException('Document is required.');
        }
        Database.delete([SELECT Id FROM ERP_Document__c WHERE Id = :documentId WITH SYSTEM_MODE LIMIT 1], AccessLevel.SYSTEM_MODE);
    }

    private static DashboardDTO buildDashboard(List<ItemDTO> items, List<CustomerDTO> customers, List<DocumentDTO> documents) {
        DashboardDTO dash = new DashboardDTO();
        dash.totalReceivables = 0;
        dash.currentReceivables = 0;
        dash.overdueReceivables = 0;
        dash.totalPayables = 0;
        dash.currentPayables = 0;
        dash.overduePayables = 0;
        dash.totalIncome = 0;
        dash.totalExpenses = 0;
        dash.itemCount = items == null ? 0 : items.size();
        dash.customerCount = customers == null ? 0 : customers.size();
        dash.draftCount = 0;
        dash.activeCount = 0;
        if (items != null) {
            for (ItemDTO item : items) {
                if (item.status == 'Draft') {
                    dash.draftCount++;
                } else {
                    dash.activeCount++;
                }
            }
        }
        if (documents != null) {
            for (DocumentDTO doc : documents) {
                Decimal amt = doc.totalAmount == null ? 0 : doc.totalAmount;
                String type = doc.documentType;
                String status = doc.status;
                if (type == 'Invoice' || type == 'Recurring Invoice') {
                    dash.totalIncome += amt;
                    if (status == 'Draft') {
                        dash.currentReceivables += amt;
                    } else {
                        dash.totalReceivables += amt;
                    }
                } else if (type == 'Vendor Bill' || type == 'Purchase Order') {
                    dash.totalPayables += amt;
                    dash.totalExpenses += amt;
                    if (status == 'Draft') {
                        dash.currentPayables += amt;
                    } else {
                        dash.overduePayables += amt;
                    }
                } else if (type == 'Credit Note') {
                    dash.totalReceivables = Math.max(0, dash.totalReceivables - amt);
                }
            }
        }
        return dash;
    }

    private static List<String> distinctItemValues(String fieldApi) {
        Set<String> allowed = new Set<String>{
            'Unit__c', 'Sales_Account__c', 'Purchase_Account__c', 'Preferred_Vendor__c'
        };
        if (!allowed.contains(fieldApi)) {
            return new List<String>();
        }
        return distinctFromQuery('ERP_Item__c', fieldApi);
    }

    private static List<String> distinctCustomerValues(String fieldApi) {
        Set<String> allowed = new Set<String>{
            'Name', 'Accounts_Receivable__c', 'Payment_Terms__c'
        };
        if (!allowed.contains(fieldApi)) {
            return new List<String>();
        }
        return distinctFromQuery('ERP_Customer__c', fieldApi);
    }

    private static List<String> distinctFromQuery(String objectApi, String fieldApi) {
        Set<String> values = new Set<String>();
        for (SObject rec : Database.query(
            'SELECT ' + fieldApi + ' FROM ' + objectApi + ' WHERE ' + fieldApi + ' != null ORDER BY ' + fieldApi + ' LIMIT 200',
            AccessLevel.SYSTEM_MODE
        )) {
            String val = String.valueOf(rec.get(fieldApi));
            if (String.isNotBlank(val)) {
                values.add(val);
            }
        }
        List<String> sorted = new List<String>(values);
        sorted.sort();
        return sorted;
    }

    private static ItemDTO toItemDto(ERP_Item__c rec) {
        ItemDTO dto = new ItemDTO();
        dto.id = rec.Id;
        dto.name = rec.Name;
        dto.itemType = rec.Type__c;
        dto.unit = rec.Unit__c;
        dto.category = rec.Category__c;
        dto.sku = rec.SKU__c;
        dto.sellingPrice = rec.Selling_Price__c;
        dto.salesAccount = rec.Sales_Account__c;
        dto.salesDescription = rec.Sales_Description__c;
        dto.costPrice = rec.Cost_Price__c;
        dto.purchaseAccount = rec.Purchase_Account__c;
        dto.purchaseDescription = rec.Purchase_Description__c;
        dto.taxCode = rec.Tax_Code__c;
        dto.preferredVendor = rec.Preferred_Vendor__c;
        dto.trackInventory = rec.Track_Inventory__c;
        dto.salesEnabled = rec.Sales_Enabled__c;
        dto.purchaseEnabled = rec.Purchase_Enabled__c;
        dto.status = rec.Status__c;
        dto.lastModified = rec.LastModifiedDate == null ? null : rec.LastModifiedDate.format();
        return dto;
    }

    private static CustomerDTO toCustomerDto(ERP_Customer__c rec) {
        CustomerDTO dto = new CustomerDTO();
        dto.id = rec.Id;
        dto.displayName = rec.Name;
        dto.customerType = rec.Customer_Type__c;
        dto.salutation = rec.Salutation__c;
        dto.firstName = rec.First_Name__c;
        dto.lastName = rec.Last_Name__c;
        dto.companyName = rec.Company_Name__c;
        dto.emailAddress = rec.Email__c;
        dto.workPhone = rec.Work_Phone__c;
        dto.mobile = rec.Mobile__c;
        dto.customerLanguage = rec.Customer_Language__c;
        dto.pan = rec.PAN__c;
        dto.gstin = rec.GSTIN__c;
        dto.currencyCode = rec.Currency_Code__c;
        dto.accountsReceivable = rec.Accounts_Receivable__c;
        dto.accountsPayable = rec.Accounts_Payable__c;
        dto.openingBalance = rec.Opening_Balance__c;
        dto.paymentTerms = rec.Payment_Terms__c;
        dto.portalAccess = rec.Portal_Access__c;
        dto.billingAddress = rec.Billing_Address__c;
        dto.shippingAddress = rec.Shipping_Address__c;
        dto.billingAttention = rec.Billing_Attention__c;
        dto.billingCountry = rec.Billing_Country__c;
        dto.billingStreet1 = rec.Billing_Street_1__c;
        dto.billingStreet2 = rec.Billing_Street_2__c;
        dto.billingCity = rec.Billing_City__c;
        dto.billingState = rec.Billing_State__c;
        dto.billingPin = rec.Billing_Pin__c;
        dto.billingPhone = rec.Billing_Phone__c;
        dto.billingFax = rec.Billing_Fax__c;
        dto.shippingAttention = rec.Shipping_Attention__c;
        dto.shippingCountry = rec.Shipping_Country__c;
        dto.shippingStreet1 = rec.Shipping_Street_1__c;
        dto.shippingStreet2 = rec.Shipping_Street_2__c;
        dto.shippingCity = rec.Shipping_City__c;
        dto.shippingState = rec.Shipping_State__c;
        dto.shippingPin = rec.Shipping_Pin__c;
        dto.shippingPhone = rec.Shipping_Phone__c;
        dto.shippingFax = rec.Shipping_Fax__c;
        dto.contactPersons = rec.Contact_Persons__c;
        dto.customFields = rec.Custom_Fields__c;
        dto.reportingTags = rec.Reporting_Tags__c;
        dto.remarks = rec.Remarks__c;
        dto.status = rec.Status__c;
        dto.lastModified = rec.LastModifiedDate == null ? null : rec.LastModifiedDate.format();
        return dto;
    }

    private static DocumentDTO toDocumentDto(ERP_Document__c rec) {
        DocumentDTO dto = new DocumentDTO();
        dto.id = rec.Id;
        dto.documentType = rec.Document_Type__c;
        dto.documentNumber = rec.Name;
        dto.customerName = rec.Customer_Name__c;
        dto.referenceNumber = rec.Reference__c;
        dto.docDate = rec.Doc_Date__c == null ? null : String.valueOf(rec.Doc_Date__c);
        dto.expiryDate = rec.Expiry_Date__c == null ? null : String.valueOf(rec.Expiry_Date__c);
        dto.expectedShipmentDate = rec.Expected_Shipment_Date__c == null ? null : String.valueOf(rec.Expected_Shipment_Date__c);
        dto.dueDate = rec.Due_Date__c == null ? null : String.valueOf(rec.Due_Date__c);
        dto.salesperson = rec.Salesperson__c;
        dto.projectName = rec.Project_Name__c;
        dto.subject = rec.Subject__c;
        dto.paymentTerms = rec.Payment_Terms__c;
        dto.deliveryMethod = rec.Delivery_Method__c;
        dto.orderNumber = rec.Order_Number__c;
        dto.accountsReceivable = rec.Accounts_Receivable__c;
        dto.lineItemsJson = rec.Line_Items_JSON__c;
        dto.subTotal = rec.Sub_Total__c;
        dto.discountPercent = rec.Discount_Percent__c;
        dto.taxAmount = rec.Tax_Amount__c;
        dto.adjustment = rec.Adjustment__c;
        dto.totalAmount = rec.Total__c;
        dto.taxType = rec.Tax_Type__c;
        dto.taxName = rec.Tax_Name__c;
        dto.currencyCode = rec.Currency__c;
        dto.customerNotes = rec.Customer_Notes__c;
        dto.termsConditions = rec.Terms_Conditions__c;
        dto.attachmentName = rec.Attachment_Name__c;
        dto.discountLevel = rec.Discount_Level__c;
        dto.giveDiscounts = rec.Give_Discounts__c;
        dto.addAdjustments = rec.Add_Adjustments__c;
        dto.addShipping = rec.Add_Shipping__c;
        dto.rounding = rec.Rounding__c;
        dto.taxForSubscriptions = rec.Tax_For_Subscriptions__c;
        dto.status = rec.Status__c;
        dto.lastModified = rec.LastModifiedDate == null ? null : rec.LastModifiedDate.format();
        return dto;
    }

    @AuraEnabled
    public static EmailResultDTO sendVoucherEmail(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to send.');
        }
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        String toAddress = textValue(payload.get('toAddress'));
        String subject = defaultText(textValue(payload.get('subject')), 'Journal voucher');
        String htmlBody = defaultText(textValue(payload.get('htmlBody')), '');
        String plainBody = textValue(payload.get('plainBody'));
        if (String.isBlank(plainBody)) {
            plainBody = htmlBody.replaceAll('<[^>]+>', ' ');
        }
        if (String.isBlank(toAddress) || !toAddress.contains('@')) {
            throw new AuraHandledException('Enter a valid email address.');
        }
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toAddress });
        String cc = textValue(payload.get('ccAddress'));
        if (String.isNotBlank(cc) && cc.contains('@')) {
            mail.setCcAddresses(new List<String>{ cc });
        }
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(plainBody);
        mail.setSaveAsActivity(false);
        EmailResultDTO dto = new EmailResultDTO();
        dto.toAddress = toAddress;
        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
            if (results != null && !results.isEmpty() && results[0].isSuccess()) {
                dto.sent = true;
                dto.message = 'Voucher emailed to ' + toAddress + '.';
                return dto;
            }
            String errorText = 'The org could not send the email.';
            if (results != null && !results.isEmpty() && results[0].getErrors() != null && !results[0].getErrors().isEmpty()) {
                errorText = results[0].getErrors()[0].getMessage();
            }
            throw new AuraHandledException(errorText);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class EmailResultDTO {
        @AuraEnabled public Boolean sent;
        @AuraEnabled public String message;
        @AuraEnabled public String toAddress;
    }

    private static Date dateValue(Object value) {
        String raw = textValue(value);
        if (String.isBlank(raw)) {
            return null;
        }
        try {
            return Date.valueOf(raw);
        } catch (Exception e) {
            return null;
        }
    }

    private static void applyUomAndCategory(ERP_Item__c rec, Map<String, Object> payload) {
        String unitChoice = textValue(payload.get('unitChoice'));
        String unitCustom = textValue(payload.get('unitCustom'));
        String unit = textValue(payload.get('unit'));
        if (String.isBlank(unitChoice)) {
            unitChoice = (unit == 'pcs' || unit == 'bundles') ? unit : (String.isBlank(unit) ? 'pcs' : 'Define new');
            if (unitChoice == 'Define new') {
                unitCustom = unit;
            }
        }
        rec.UOM__c = String.isBlank(unitChoice) ? 'pcs' : unitChoice;
        rec.Define_New_UOM__c = unitChoice == 'Define new' ? unitCustom : null;
        rec.Unit__c = unitChoice == 'Define new' ? unitCustom : unitChoice;

        String categoryChoice = textValue(payload.get('categoryChoice'));
        String categoryCustom = textValue(payload.get('categoryCustom'));
        String category = textValue(payload.get('category'));
        Set<String> known = new Set<String>{
            'Raw Materials', 'Finished Goods', 'Semi-Finished Goods', 'Trading Goods',
            'Consumables', 'Spare Parts', 'Packaging Materials', 'Services'
        };
        if (String.isBlank(categoryChoice) && String.isNotBlank(category)) {
            categoryChoice = known.contains(category) ? category : 'Define new';
            if (categoryChoice == 'Define new') {
                categoryCustom = category;
            }
        }
        if (String.isNotBlank(categoryChoice)) {
            rec.Category_List__c = categoryChoice;
        }
        rec.Define_New_Category__c = categoryChoice == 'Define new' ? categoryCustom : null;
        String resolvedCategory = categoryChoice == 'Define new' ? categoryCustom : categoryChoice;
        if (String.isNotBlank(resolvedCategory)) {
            rec.Category__c = resolvedCategory;
        }
    }

    private static void putText(ERP_Item__c rec, String fieldName, String value) {
        if (String.isNotBlank(value)) {
            rec.put(fieldName, value);
        }
    }

    private static String textValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static String defaultText(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    private static Boolean boolValue(Object value, Boolean fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return String.valueOf(value) == 'true';
    }

    private static Decimal decimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}