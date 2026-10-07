/**
 * Seeds catalogue, parties, and documents the ERP screens already read.
 * Extra object types are skipped when the org picklist does not allow them.
 */
public without sharing class ERPSampleData {
    public static void ensure() {
        ensureLedgers();
        ensureApSetup();
        Integer itemCount = Database.countQuery('SELECT COUNT() FROM ERP_Item__c', AccessLevel.SYSTEM_MODE);
        if (itemCount > 0) {
            return;
        }
        seed();
    }

    public static void ensureLedgers() {
        Integer ledgerCount = Database.countQuery('SELECT COUNT() FROM ERP_Ledger__c', AccessLevel.SYSTEM_MODE);
        if (ledgerCount > 0) {
            return;
        }
        List<ERP_Ledger__c> rows = new List<ERP_Ledger__c>{
            ledger('100000', 'Asset', 'asset', 'header', 1, 'debit', 'none', 0),
            ledger('110000', 'Current assets', 'asset', 'header', 2, 'debit', 'none', 0),
            ledger('111000', 'Cash and bank books', 'asset', 'header', 3, 'debit', 'none', 0),
            ledger('111100', 'Cash on hand', 'asset', 'posting', 4, 'debit', 'cash', 25000),
            ledger('111200', 'Operating bank book', 'asset', 'posting', 4, 'debit', 'bank', 180000),
            ledger('112000', 'Receivables', 'asset', 'header', 3, 'debit', 'none', 0),
            ledger('112100', 'Trade receivable', 'asset', 'posting', 4, 'debit', 'receivable', 45000),
            ledger('113000', 'Stock on hand', 'asset', 'header', 3, 'debit', 'none', 0),
            ledger('113100', 'Finished goods', 'asset', 'posting', 4, 'debit', 'none', 62000),
            ledger('200000', 'Liability', 'liability', 'header', 1, 'credit', 'none', 0),
            ledger('211000', 'Trade payable', 'liability', 'posting', 3, 'credit', 'payable', 38000),
            ledger('212000', 'GST payable', 'liability', 'posting', 3, 'credit', 'none', 12000),
            ledger('300000', 'Equity', 'equity', 'header', 1, 'credit', 'none', 0),
            ledger('310000', 'Owner capital', 'equity', 'posting', 2, 'credit', 'none', 500000),
            ledger('400000', 'Income', 'income', 'header', 1, 'credit', 'none', 0),
            ledger('410000', 'Outward sales', 'income', 'posting', 2, 'credit', 'none', 0),
            ledger('500000', 'Cost of goods', 'cogs', 'header', 1, 'debit', 'none', 0),
            ledger('510000', 'Cost of goods sold', 'cogs', 'posting', 2, 'debit', 'none', 0),
            ledger('600000', 'Spend', 'spend', 'header', 1, 'debit', 'none', 0),
            ledger('610000', 'People cost', 'spend', 'posting', 2, 'debit', 'none', 0),
            ledger('620000', 'Rent and occupancy', 'spend', 'posting', 2, 'debit', 'none', 0),
            ledger('630000', 'Utilities', 'spend', 'posting', 2, 'debit', 'none', 0)
        };
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
        Map<String, Id> byCode = new Map<String, Id>();
        for (ERP_Ledger__c rec : rows) {
            byCode.put(rec.Code__c, rec.Id);
        }
        Map<String, String> parents = new Map<String, String>{
            '110000' => '100000',
            '111000' => '110000',
            '111100' => '111000',
            '111200' => '111000',
            '112000' => '110000',
            '112100' => '112000',
            '113000' => '110000',
            '113100' => '113000',
            '211000' => '200000',
            '212000' => '200000',
            '310000' => '300000',
            '410000' => '400000',
            '510000' => '500000',
            '610000' => '600000',
            '620000' => '600000',
            '630000' => '600000'
        };
        List<ERP_Ledger__c> updates = new List<ERP_Ledger__c>();
        for (String code : parents.keySet()) {
            updates.add(new ERP_Ledger__c(Id = byCode.get(code), Parent_Ledger__c = byCode.get(parents.get(code))));
        }
        Database.update(updates, AccessLevel.SYSTEM_MODE);
    }

    static ERP_Ledger__c ledger(String code, String name, String drawer, String kind, Integer level, String side, String control, Decimal opening) {
        return new ERP_Ledger__c(
            Name = name,
            Code__c = code,
            Drawer__c = drawer,
            Kind__c = kind,
            Level__c = level,
            Normal_Side__c = side,
            Control_Use__c = control,
            Opening_Balance__c = opening,
            Active__c = true
        );
    }

    static void ensureApSetup() {
        List<ERP_Customer__c> parties = [
            SELECT Id
            FROM ERP_Customer__c
            WHERE Accounts_Payable__c = null
            WITH SYSTEM_MODE
            LIMIT 200
        ];
        for (ERP_Customer__c rec : parties) {
            rec.Accounts_Payable__c = '211000 Trade payable';
        }
        if (!parties.isEmpty()) {
            Database.update(parties, AccessLevel.SYSTEM_MODE);
        }
        List<ERP_Item__c> goods = [
            SELECT Id
            FROM ERP_Item__c
            WHERE Tax_Code__c = null AND Type__c = 'Goods' AND Purchase_Enabled__c = true
            WITH SYSTEM_MODE
            LIMIT 200
        ];
        for (ERP_Item__c rec : goods) {
            rec.Tax_Code__c = 'GST 18%';
        }
        if (!goods.isEmpty()) {
            Database.update(goods, AccessLevel.SYSTEM_MODE);
        }
    }

    public static void seed() {
        Map<String, ERP_Item__c> items = seedItems();
        Map<String, ERP_Customer__c> parties = seedParties();
        seedDocuments(parties, items);
    }

    static Map<String, ERP_Item__c> seedItems() {
        List<ERP_Item__c> rows = new List<ERP_Item__c>{
            new ERP_Item__c(
                Name = 'Notebook',
                Type__c = 'Goods',
                Unit__c = 'pcs',
                SKU__c = 'GDS-NOTE100',
                Selling_Price__c = 450,
                Sales_Account__c = 'Outward sales',
                Sales_Description__c = 'Ruled notebook for office and field use.',
                Cost_Price__c = 180,
                Purchase_Account__c = 'Cost of goods sold',
                Purchase_Description__c = 'Bought from the supply register in packs of 20.',
                Preferred_Vendor__c = 'Nila Supplies',
                Track_Inventory__c = true,
                Sales_Enabled__c = true,
                Purchase_Enabled__c = true,
                Status__c = 'Active'
            ),
            new ERP_Item__c(
                Name = 'Finished kit',
                Type__c = 'Goods',
                Unit__c = 'pcs',
                SKU__c = 'KIT-100',
                Selling_Price__c = 4500,
                Sales_Account__c = 'Outward sales',
                Sales_Description__c = 'Finished kit for outward fulfilment.',
                Cost_Price__c = 1800,
                Purchase_Account__c = 'Cost of goods sold',
                Purchase_Description__c = 'Bought as a complete assembly from the supply register.',
                Preferred_Vendor__c = 'Nila Supplies',
                Track_Inventory__c = true,
                Sales_Enabled__c = true,
                Purchase_Enabled__c = true,
                Status__c = 'Active'
            ),
            new ERP_Item__c(
                Name = 'Installation visit',
                Type__c = 'Service',
                Unit__c = 'hrs',
                SKU__c = 'INST-10',
                Selling_Price__c = 8000,
                Sales_Account__c = 'Outward sales',
                Sales_Description__c = 'On-site installation and handover.',
                Cost_Price__c = 0,
                Purchase_Account__c = 'People cost',
                Purchase_Enabled__c = false,
                Track_Inventory__c = false,
                Sales_Enabled__c = true,
                Status__c = 'Active'
            ),
            new ERP_Item__c(
                Name = 'Spare pack',
                Type__c = 'Goods',
                Unit__c = 'pcs',
                SKU__c = 'SPR-40',
                Selling_Price__c = 1200,
                Sales_Account__c = 'Outward sales',
                Sales_Description__c = 'Spare pack used on tax invoices and returns.',
                Cost_Price__c = 600,
                Purchase_Account__c = 'Cost of goods sold',
                Preferred_Vendor__c = 'Nila Supplies',
                Track_Inventory__c = true,
                Sales_Enabled__c = true,
                Purchase_Enabled__c = true,
                Status__c = 'Active'
            )
        };
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
        return new Map<String, ERP_Item__c>{
            'note' => rows[0],
            'kit' => rows[1],
            'visit' => rows[2],
            'spare' => rows[3]
        };
    }

    static Map<String, ERP_Customer__c> seedParties() {
        List<ERP_Customer__c> rows = new List<ERP_Customer__c>{
            party('Acme Traders', 'Business', 'accounts@acmetraders.example', '33AABCU9603R1ZM', 'AABCU9603R', 'Chennai', 'Tamil Nadu', '600001', 0),
            party('Harbor Goods Pvt Ltd', 'Business', 'finance@harbor.example', '27AABCH1234P1Z5', 'AABCH1234P', 'Mumbai', 'Maharashtra', '400001', 0),
            party('Nila Supplies', 'Business', 'billing@nilasupplies.example', '29AABCN5678L1Z2', 'AABCN5678L', 'Bengaluru', 'Karnataka', '560001', 0)
        };
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
        return new Map<String, ERP_Customer__c>{
            'acme' => rows[0],
            'harbor' => rows[1],
            'nila' => rows[2]
        };
    }

    static void seedDocuments(Map<String, ERP_Customer__c> parties, Map<String, ERP_Item__c> items) {
        Date today = Date.today();
        String kitLine = lines(items.get('kit').Name, 10, 4500, '8479');
        String visitLine = lines(items.get('visit').Name, 1, 8000, '9987');
        String spareLine = lines(items.get('spare').Name, 10, 600, '8538');
        String noteLine = lines(items.get('note').Name, 40, 450, '4820');
        List<ERP_Document__c> rows = new List<ERP_Document__c>();
        addDoc(rows, 'QT-00001', 'Quote', parties.get('acme'), today.addDays(-12), 45000, 8100, 53100, 'Draft', kitLine);
        addDoc(rows, 'SO-00001', 'Sales Order', parties.get('acme'), today.addDays(-8), 45000, 8100, 53100, 'Sent', kitLine);
        addDoc(rows, 'TI-00001', 'Invoice', parties.get('acme'), today.addDays(-5), 45000, 8100, 53100, 'Sent', kitLine);
        addDoc(rows, 'TI-00002', 'Invoice', parties.get('harbor'), today, 8000, 1440, 9440, 'Draft', visitLine);
        addDoc(rows, 'CN-00001', 'Credit Note', parties.get('acme'), today.addDays(-1), 1200, 216, 1416, 'Sent', lines(items.get('spare').Name, 1, 1200, '8538'));
        addDoc(rows, 'DC-00001', 'Delivery Challan', parties.get('acme'), today.addDays(-4), 45000, 0, 45000, 'Sent', kitLine);
        addDoc(rows, 'RI-00001', 'Recurring Invoice', parties.get('harbor'), today.addDays(-20), 8000, 1440, 9440, 'Sent', visitLine);
        addDoc(rows, 'PO-00001', 'Purchase Order', parties.get('nila'), today.addDays(-10), 6000, 1080, 7080, 'Sent', spareLine);
        addDoc(rows, 'BILL-00001', 'Vendor Bill', parties.get('nila'), today.addDays(-6), 6000, 1080, 7080, 'Sent', spareLine);
        addDoc(rows, 'GR-00001', 'Goods Receipt', parties.get('nila'), today.addDays(-6), 6000, 0, 6000, 'Sent', spareLine);
        addDoc(rows, 'QT-00002', 'Quote', parties.get('harbor'), today.addDays(-3), 18000, 3240, 21240, 'Sent', noteLine);
        if (rows.isEmpty()) {
            return;
        }
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }

    static void addDoc(
        List<ERP_Document__c> rows,
        String num,
        String type,
        ERP_Customer__c party,
        Date whenDate,
        Decimal sub,
        Decimal tax,
        Decimal total,
        String status,
        String lineJson
    ) {
        if (!allowedTypes().contains(type)) {
            return;
        }
        rows.add(new ERP_Document__c(
            Name = num,
            Document_Type__c = type,
            Customer_Name__c = party.Name,
            Doc_Date__c = whenDate,
            Sub_Total__c = sub,
            Tax_Amount__c = tax,
            Total__c = total,
            Status__c = status,
            Line_Items_JSON__c = lineJson,
            Payment_Terms__c = '30 days',
            Accounts_Receivable__c = 'Trade receivable',
            Subject__c = type + ' for ' + party.Name
        ));
    }

    static Set<String> allowedTypes() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : ERP_Document__c.Document_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    static ERP_Customer__c party(
        String name,
        String kind,
        String email,
        String gstin,
        String pan,
        String city,
        String state,
        String pin,
        Decimal opening
    ) {
        return new ERP_Customer__c(
            Name = name,
            Company_Name__c = name,
            Customer_Type__c = kind,
            Email__c = email,
            GSTIN__c = gstin,
            PAN__c = pan,
            Billing_City__c = city,
            Billing_State__c = state,
            Billing_Pin__c = pin,
            Billing_Country__c = 'India',
            Currency_Code__c = 'INR- Indian Rupee',
            Payment_Terms__c = '30 days',
            Accounts_Receivable__c = 'Trade receivable',
            Opening_Balance__c = opening,
            Status__c = 'Active'
        );
    }

    static String lines(String details, Decimal qty, Decimal rate, String hsn) {
        return JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'details' => details,
                'qty' => qty,
                'rate' => rate,
                'amount' => qty * rate,
                'hsn' => hsn,
                'taxPercent' => 18
            }
        });
    }
}