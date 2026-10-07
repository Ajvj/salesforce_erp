/**
 * Salesforce persistence for journals, expenses, purchases, projects, and timesheets.
 */
public with sharing class ERPBooksController {
    public class LineDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String ledger;
        @AuraEnabled public String particulars;
        @AuraEnabled public String party;
        @AuraEnabled public Decimal debit;
        @AuraEnabled public Decimal credit;
    }

    public class JournalDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String journalNumber;
        @AuraEnabled public String journalDate;
        @AuraEnabled public String journalReverseDate;
        @AuraEnabled public String journalReference;
        @AuraEnabled public String journalNarration;
        @AuraEnabled public String journalBasis;
        @AuraEnabled public String journalCurrency;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal total;
        @AuraEnabled public String sourceKey;
        @AuraEnabled public List<LineDTO> lines;
    }

    public class ExpenseDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String entryNumber;
        @AuraEnabled public String kind;
        @AuraEnabled public String entryDate;
        @AuraEnabled public String account;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String paidThrough;
        @AuraEnabled public String vendor;
        @AuraEnabled public String customer;
        @AuraEnabled public String invoice;
        @AuraEnabled public String notes;
        @AuraEnabled public String fileName;
        @AuraEnabled public String journalNumber;
        @AuraEnabled public String status;
    }

    public class RecurringDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String profileName;
        @AuraEnabled public String vendor;
        @AuraEnabled public String customer;
        @AuraEnabled public String repeatEvery;
        @AuraEnabled public String startDate;
        @AuraEnabled public String nextRun;
        @AuraEnabled public String endsOn;
        @AuraEnabled public Boolean neverExpires;
        @AuraEnabled public String expenseAccount;
        @AuraEnabled public String paidThrough;
        @AuraEnabled public String accountsPayable;
        @AuraEnabled public String paymentTerms;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String notes;
        @AuraEnabled public String status;
        @AuraEnabled public String lines;
    }

    public class PaymentDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String paymentNumber;
        @AuraEnabled public String kind;
        @AuraEnabled public String vendor;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String bill;
        @AuraEnabled public String paymentDate;
        @AuraEnabled public String paymentMode;
        @AuraEnabled public String paidThrough;
        @AuraEnabled public String status;
        @AuraEnabled public String journalNumber;
        @AuraEnabled public String reference;
    }

    public class TaskDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean billable;
    }

    public class ProjectDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String projectName;
        @AuraEnabled public String projectCode;
        @AuraEnabled public String customer;
        @AuraEnabled public String billingMethod;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal costBudget;
        @AuraEnabled public Decimal revenueBudget;
        @AuraEnabled public String status;
        @AuraEnabled public String users;
        @AuraEnabled public List<TaskDTO> tasks;
    }

    public class TimesheetDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String entryNumber;
        @AuraEnabled public String staff;
        @AuraEnabled public String job;
        @AuraEnabled public Decimal hours;
        @AuraEnabled public String entryDate;
        @AuraEnabled public String status;
    }

    public class BooksDTO {
        @AuraEnabled public List<JournalDTO> journals;
        @AuraEnabled public List<ExpenseDTO> expenses;
        @AuraEnabled public List<RecurringDTO> recurringExpenses;
        @AuraEnabled public List<RecurringDTO> recurringBills;
        @AuraEnabled public List<PaymentDTO> paymentsMade;
        @AuraEnabled public List<ProjectDTO> projects;
        @AuraEnabled public List<TimesheetDTO> timesheets;
    }

    @AuraEnabled
    public static BooksDTO getBooks() {
        BooksDTO data = new BooksDTO();
        data.journals = listJournals();
        data.expenses = listExpenses();
        data.recurringExpenses = listRecurringExpenses();
        data.recurringBills = listRecurringBills();
        data.paymentsMade = listPayments();
        data.projects = listProjects();
        data.timesheets = listTimesheets();
        return data;
    }

    @AuraEnabled
    public static Id saveJournal(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        String recNumber = clip(defaultText(textValue(payload.get('journalNumber')), 'JV-00001'), 80);
        ERP_Journal__c rec = loadJournal(textValue(payload.get('id')), recNumber);
        rec.Name = recNumber;
        rec.Posting_Date__c = dateValue(payload.get('journalDate'));
        rec.Reverse_On__c = dateValue(payload.get('journalReverseDate'));
        rec.Reference__c = clip(textValue(payload.get('journalReference')), 80);
        rec.Narration__c = clip(textValue(payload.get('journalNarration')), 255);
        rec.Basis__c = pick(textValue(payload.get('journalBasis')), new Set<String>{ 'accrual_cash', 'cash' }, 'accrual_cash');
        rec.Currency_Code__c = clip(defaultText(textValue(payload.get('journalCurrency')), 'INR'), 40);
        rec.Status__c = pick(textValue(payload.get('status')), new Set<String>{ 'Draft', 'Posted', 'Reversed' }, 'Posted');
        rec.Total_Debit__c = decimalValue(payload.get('total'));
        rec.Total_Credit__c = rec.Total_Debit__c;
        rec.Source_Document__c = findDocument(textValue(payload.get('sourceKey')));

        List<Map<String, Object>> rawLines = new List<Map<String, Object>>();
        Set<String> ledgerLabels = new Set<String>();
        Set<String> partyNames = new Set<String>();
        String headerParty = firstParty(payload);
        if (String.isNotBlank(headerParty)) {
            partyNames.add(headerParty);
        }
        for (Object raw : listValue(payload.get('lines'))) {
            Map<String, Object> line = (Map<String, Object>) raw;
            String ledgerLabel = textValue(line.get('ledger'));
            if (String.isBlank(ledgerLabel)) {
                continue;
            }
            rawLines.add(line);
            ledgerLabels.add(ledgerLabel);
            String party = textValue(line.get('party'));
            if (String.isNotBlank(party)) {
                partyNames.add(party);
            }
        }
        Map<String, Id> ledgerIds = ensureLedgers(ledgerLabels);
        Map<String, Id> customerIds = customersByName(partyNames);
        rec.Customer__c = customerIds.get(headerParty);
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);

        List<ERP_Journal_Line__c> stale = [
            SELECT Id FROM ERP_Journal_Line__c WHERE Journal__c = :rec.Id WITH SYSTEM_MODE
        ];
        if (!stale.isEmpty()) {
            Database.delete(stale, AccessLevel.SYSTEM_MODE);
        }
        List<ERP_Journal_Line__c> lines = new List<ERP_Journal_Line__c>();
        Integer n = 1;
        for (Map<String, Object> line : rawLines) {
            String ledgerLabel = textValue(line.get('ledger'));
            Id ledgerId = ledgerIds.get(ledgerLabel);
            if (ledgerId == null) {
                throw new AuraHandledException('Ledger was not stored: ' + ledgerLabel);
            }
            lines.add(new ERP_Journal_Line__c(
                Journal__c = rec.Id,
                Line_Number__c = n,
                Ledger__c = ledgerId,
                Particulars__c = clip(textValue(line.get('particulars')), 255),
                Party_Name__c = clip(textValue(line.get('party')), 255),
                Customer__c = customerIds.get(textValue(line.get('party'))),
                Debit__c = decimalValue(line.get('debit')),
                Credit__c = decimalValue(line.get('credit'))
            ));
            n++;
        }
        for (Integer start = 0; start < lines.size(); start += 200) {
            Integer last = Math.min(start + 200, lines.size());
            List<ERP_Journal_Line__c> chunk = new List<ERP_Journal_Line__c>();
            for (Integer i = start; i < last; i++) {
                chunk.add(lines[i]);
            }
            Database.insert(chunk, AccessLevel.SYSTEM_MODE);
        }
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveExpense(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        String recNumber = defaultText(textValue(payload.get('number')), 'EXP-00001');
        ERP_Expense__c rec = new ERP_Expense__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        } else {
            List<ERP_Expense__c> found = [SELECT Id FROM ERP_Expense__c WHERE Name = :recNumber WITH SYSTEM_MODE LIMIT 1];
            if (!found.isEmpty()) {
                rec.Id = found[0].Id;
            }
        }
        rec.Name = recNumber;
        rec.Kind__c = defaultText(textValue(payload.get('kind')), 'expense');
        rec.Expense_Date__c = dateValue(payload.get('date'));
        rec.Account__c = textValue(payload.get('account'));
        rec.Amount__c = decimalValue(payload.get('amount'));
        rec.Paid_Through__c = textValue(payload.get('paidThrough'));
        rec.Vendor_Name__c = textValue(payload.get('vendor'));
        rec.Invoice_Number__c = textValue(payload.get('invoice'));
        rec.Notes__c = textValue(payload.get('notes'));
        rec.File_Name__c = textValue(payload.get('fileName'));
        rec.Status__c = defaultText(textValue(payload.get('status')), 'Posted');
        rec.Customer__c = findCustomer(firstNonBlank(textValue(payload.get('customer')), textValue(payload.get('vendor'))));
        rec.Journal__c = findJournal(textValue(payload.get('journalNumber')));
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveRecurringExpense(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        ERP_Recurring_Expense__c rec = new ERP_Recurring_Expense__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        }
        rec.Name = defaultText(textValue(payload.get('profileName')), 'Recurring expense');
        rec.Repeat_Every__c = textValue(payload.get('repeatEvery'));
        rec.Start_Date__c = dateValue(payload.get('startDate'));
        rec.Next_Run__c = dateValue(firstNonBlank(textValue(payload.get('nextRun')), textValue(payload.get('startDate'))));
        rec.Ends_On__c = dateValue(payload.get('endsOn'));
        rec.Never_Expires__c = boolValue(payload.get('neverExpires'), true);
        rec.Expense_Account__c = textValue(payload.get('expenseAccount'));
        rec.Amount__c = decimalValue(payload.get('amount'));
        rec.Paid_Through__c = textValue(payload.get('paidThrough'));
        rec.Vendor_Name__c = textValue(payload.get('vendor'));
        rec.Notes__c = textValue(payload.get('notes'));
        rec.Status__c = defaultText(textValue(payload.get('status')), 'Active');
        rec.Customer__c = findCustomer(firstNonBlank(textValue(payload.get('customer')), textValue(payload.get('vendor'))));
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveRecurringBill(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        ERP_Recurring_Bill__c rec = new ERP_Recurring_Bill__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        }
        rec.Name = defaultText(textValue(payload.get('profileName')), 'Recurring bill');
        rec.Vendor_Name__c = textValue(payload.get('vendor'));
        rec.Repeat_Every__c = textValue(payload.get('repeatEvery'));
        rec.Start_Date__c = dateValue(payload.get('startDate'));
        rec.Next_Run__c = dateValue(firstNonBlank(textValue(payload.get('nextRun')), textValue(payload.get('startDate'))));
        rec.Ends_On__c = dateValue(payload.get('endsOn'));
        rec.Never_Expires__c = boolValue(payload.get('neverExpires'), true);
        rec.Accounts_Payable__c = textValue(payload.get('accountsPayable'));
        rec.Payment_Terms__c = textValue(payload.get('paymentTerms'));
        rec.Amount__c = decimalValue(payload.get('amount'));
        rec.Line_Items_JSON__c = lineJson(payload.get('lines'));
        rec.Status__c = defaultText(textValue(payload.get('status')), 'Active');
        rec.Customer__c = findCustomer(textValue(payload.get('vendor')));
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id savePayment(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        String recNumber = defaultText(textValue(payload.get('paymentNumber')), 'PAY-00001');
        ERP_Payment__c rec = new ERP_Payment__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        } else {
            List<ERP_Payment__c> found = [SELECT Id FROM ERP_Payment__c WHERE Name = :recNumber WITH SYSTEM_MODE LIMIT 1];
            if (!found.isEmpty()) {
                rec.Id = found[0].Id;
            }
        }
        String kind = defaultText(textValue(payload.get('kind')), 'Vendor Payment');
        rec.Name = recNumber;
        rec.Move_Type__c = paymentType(kind);
        rec.Move_Date__c = dateValue(payload.get('paymentDate'));
        rec.Amount__c = decimalValue(payload.get('amount'));
        rec.Mode__c = textValue(payload.get('paymentMode'));
        rec.Reference__c = firstNonBlank(textValue(payload.get('reference')), textValue(payload.get('bill')));
        rec.Notes__c = kind;
        rec.Status__c = pick(textValue(payload.get('status')), new Set<String>{ 'Draft', 'Cleared', 'Paid' }, 'Paid');
        rec.Customer__c = findCustomer(textValue(payload.get('vendor')));
        rec.Document__c = findDocument(firstBill(textValue(payload.get('bill'))));
        rec.Journal__c = findJournal(textValue(payload.get('journalNumber')));
        rec.Bank_Ledger__c = ensureLedger(textValue(payload.get('paidThrough')));
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveProject(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        String name = defaultText(textValue(payload.get('projectName')), 'Project');
        ERP_Project__c rec = new ERP_Project__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        } else {
            List<ERP_Project__c> found = [SELECT Id FROM ERP_Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1];
            if (!found.isEmpty()) {
                rec.Id = found[0].Id;
            }
        }
        rec.Name = name;
        rec.Project_Code__c = textValue(payload.get('projectCode'));
        rec.Billing_Method__c = textValue(payload.get('billingMethod'));
        rec.Description__c = textValue(payload.get('description'));
        rec.Cost_Budget__c = decimalValue(payload.get('costBudget'));
        rec.Revenue_Budget__c = decimalValue(payload.get('revenueBudget'));
        rec.Users_JSON__c = lineJson(payload.get('users'));
        rec.Status__c = defaultText(textValue(payload.get('status')), 'Active');
        rec.Customer__c = findCustomer(textValue(payload.get('customer')));
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);

        List<ERP_Project_Task__c> stale = [
            SELECT Id FROM ERP_Project_Task__c WHERE Project__c = :rec.Id WITH SYSTEM_MODE
        ];
        if (!stale.isEmpty()) {
            Database.delete(stale, AccessLevel.SYSTEM_MODE);
        }
        List<ERP_Project_Task__c> tasks = new List<ERP_Project_Task__c>();
        for (Object raw : listValue(payload.get('tasks'))) {
            Map<String, Object> row = (Map<String, Object>) raw;
            String taskName = textValue(row.get('name'));
            if (String.isBlank(taskName)) {
                continue;
            }
            tasks.add(new ERP_Project_Task__c(
                Name = taskName,
                Project__c = rec.Id,
                Description__c = textValue(row.get('description')),
                Billable__c = boolValue(row.get('billable'), true)
            ));
        }
        if (!tasks.isEmpty()) {
            Database.insert(tasks, AccessLevel.SYSTEM_MODE);
        }
        return rec.Id;
    }

    @AuraEnabled
    public static Id saveTimesheet(String payloadJson) {
        Map<String, Object> payload = readPayload(payloadJson);
        String recNumber = defaultText(textValue(payload.get('number')), 'TS-00001');
        ERP_Timesheet__c rec = new ERP_Timesheet__c();
        Id existing = asId(textValue(payload.get('id')));
        if (existing != null) {
            rec.Id = existing;
        } else {
            List<ERP_Timesheet__c> found = [SELECT Id FROM ERP_Timesheet__c WHERE Name = :recNumber WITH SYSTEM_MODE LIMIT 1];
            if (!found.isEmpty()) {
                rec.Id = found[0].Id;
            }
        }
        String job = textValue(payload.get('job'));
        rec.Name = recNumber;
        rec.Worker_Name__c = textValue(payload.get('staff'));
        rec.Project_Name__c = job;
        rec.Hours__c = decimalValue(payload.get('hours'));
        rec.Work_Date__c = dateValue(payload.get('date'));
        rec.Status__c = pick(textValue(payload.get('status')), new Set<String>{ 'Draft', 'Approved', 'Billable', 'Non-billable' }, 'Draft');
        rec.Notes__c = textValue(payload.get('notes'));
        rec.Project__c = findProject(job);
        rec.Customer__c = projectCustomer(rec.Project__c);
        Database.upsert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    public static List<JournalDTO> listJournals() {
        List<JournalDTO> rows = new List<JournalDTO>();
        for (ERP_Journal__c rec : [
            SELECT Id, Name, Posting_Date__c, Reverse_On__c, Reference__c, Narration__c, Basis__c, Currency_Code__c,
                   Status__c, Total_Debit__c, Customer__r.Name, Source_Document__r.Name,
                   (SELECT Id, Line_Number__c, Ledger__r.Name, Ledger__r.Code__c, Particulars__c, Party_Name__c,
                           Customer__r.Name, Debit__c, Credit__c
                    FROM Journal_Lines__r
                    ORDER BY Line_Number__c)
            FROM ERP_Journal__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            JournalDTO dto = new JournalDTO();
            dto.id = rec.Id;
            dto.journalNumber = rec.Name;
            dto.journalDate = rec.Posting_Date__c == null ? null : String.valueOf(rec.Posting_Date__c);
            dto.journalReverseDate = rec.Reverse_On__c == null ? null : String.valueOf(rec.Reverse_On__c);
            dto.journalReference = rec.Reference__c;
            dto.journalNarration = rec.Narration__c;
            dto.journalBasis = rec.Basis__c;
            dto.journalCurrency = rec.Currency_Code__c;
            dto.status = rec.Status__c;
            dto.total = rec.Total_Debit__c;
            dto.sourceKey = rec.Source_Document__r == null ? null : rec.Source_Document__r.Name;
            dto.lines = new List<LineDTO>();
            for (ERP_Journal_Line__c line : rec.Journal_Lines__r) {
                LineDTO row = new LineDTO();
                row.key = line.Id;
                row.ledger = ledgerLabel(line.Ledger__r);
                row.particulars = line.Particulars__c;
                row.party = firstNonBlank(line.Party_Name__c, line.Customer__r == null ? null : line.Customer__r.Name);
                row.debit = line.Debit__c;
                row.credit = line.Credit__c;
                dto.lines.add(row);
            }
            rows.add(dto);
        }
        return rows;
    }

    public static List<ExpenseDTO> listExpenses() {
        List<ExpenseDTO> rows = new List<ExpenseDTO>();
        for (ERP_Expense__c rec : [
            SELECT Id, Name, Kind__c, Expense_Date__c, Account__c, Amount__c, Paid_Through__c, Vendor_Name__c,
                   Invoice_Number__c, Notes__c, File_Name__c, Status__c, Customer__r.Name, Journal__r.Name
            FROM ERP_Expense__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            ExpenseDTO dto = new ExpenseDTO();
            dto.id = rec.Id;
            dto.entryNumber = rec.Name;
            dto.kind = rec.Kind__c;
            dto.entryDate = rec.Expense_Date__c == null ? null : String.valueOf(rec.Expense_Date__c);
            dto.account = rec.Account__c;
            dto.amount = rec.Amount__c;
            dto.paidThrough = rec.Paid_Through__c;
            dto.vendor = rec.Vendor_Name__c;
            dto.customer = rec.Customer__r == null ? null : rec.Customer__r.Name;
            dto.invoice = rec.Invoice_Number__c;
            dto.notes = rec.Notes__c;
            dto.fileName = rec.File_Name__c;
            dto.status = rec.Status__c;
            dto.journalNumber = rec.Journal__r == null ? null : rec.Journal__r.Name;
            rows.add(dto);
        }
        return rows;
    }

    public static List<RecurringDTO> listRecurringExpenses() {
        List<RecurringDTO> rows = new List<RecurringDTO>();
        for (ERP_Recurring_Expense__c rec : [
            SELECT Id, Name, Repeat_Every__c, Start_Date__c, Next_Run__c, Ends_On__c, Never_Expires__c,
                   Expense_Account__c, Amount__c, Paid_Through__c, Vendor_Name__c, Notes__c, Status__c, Customer__r.Name
            FROM ERP_Recurring_Expense__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            RecurringDTO dto = new RecurringDTO();
            dto.id = rec.Id;
            dto.profileName = rec.Name;
            dto.repeatEvery = rec.Repeat_Every__c;
            dto.startDate = rec.Start_Date__c == null ? null : String.valueOf(rec.Start_Date__c);
            dto.nextRun = rec.Next_Run__c == null ? null : String.valueOf(rec.Next_Run__c);
            dto.endsOn = rec.Ends_On__c == null ? null : String.valueOf(rec.Ends_On__c);
            dto.neverExpires = rec.Never_Expires__c;
            dto.expenseAccount = rec.Expense_Account__c;
            dto.amount = rec.Amount__c;
            dto.paidThrough = rec.Paid_Through__c;
            dto.vendor = rec.Vendor_Name__c;
            dto.notes = rec.Notes__c;
            dto.status = rec.Status__c;
            dto.customer = rec.Customer__r == null ? null : rec.Customer__r.Name;
            rows.add(dto);
        }
        return rows;
    }

    public static List<RecurringDTO> listRecurringBills() {
        List<RecurringDTO> rows = new List<RecurringDTO>();
        for (ERP_Recurring_Bill__c rec : [
            SELECT Id, Name, Vendor_Name__c, Repeat_Every__c, Start_Date__c, Next_Run__c, Ends_On__c, Never_Expires__c,
                   Accounts_Payable__c, Payment_Terms__c, Amount__c, Line_Items_JSON__c, Status__c, Customer__r.Name
            FROM ERP_Recurring_Bill__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            RecurringDTO dto = new RecurringDTO();
            dto.id = rec.Id;
            dto.profileName = rec.Name;
            dto.vendor = rec.Vendor_Name__c;
            dto.repeatEvery = rec.Repeat_Every__c;
            dto.startDate = rec.Start_Date__c == null ? null : String.valueOf(rec.Start_Date__c);
            dto.nextRun = rec.Next_Run__c == null ? null : String.valueOf(rec.Next_Run__c);
            dto.endsOn = rec.Ends_On__c == null ? null : String.valueOf(rec.Ends_On__c);
            dto.neverExpires = rec.Never_Expires__c;
            dto.accountsPayable = rec.Accounts_Payable__c;
            dto.paymentTerms = rec.Payment_Terms__c;
            dto.amount = rec.Amount__c;
            dto.lines = rec.Line_Items_JSON__c;
            dto.status = rec.Status__c;
            dto.customer = rec.Customer__r == null ? rec.Vendor_Name__c : rec.Customer__r.Name;
            rows.add(dto);
        }
        return rows;
    }

    public static List<PaymentDTO> listPayments() {
        List<PaymentDTO> rows = new List<PaymentDTO>();
        for (ERP_Payment__c rec : [
            SELECT Id, Name, Move_Type__c, Move_Date__c, Amount__c, Mode__c, Reference__c, Notes__c, Status__c,
                   Customer__r.Name, Document__r.Name, Journal__r.Name
            FROM ERP_Payment__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            PaymentDTO dto = new PaymentDTO();
            dto.id = rec.Id;
            dto.paymentNumber = rec.Name;
            dto.kind = firstNonBlank(rec.Notes__c, rec.Move_Type__c);
            dto.vendor = rec.Customer__r == null ? null : rec.Customer__r.Name;
            dto.amount = rec.Amount__c;
            dto.bill = rec.Document__r == null ? rec.Reference__c : rec.Document__r.Name;
            dto.paymentDate = rec.Move_Date__c == null ? null : String.valueOf(rec.Move_Date__c);
            dto.paymentMode = rec.Mode__c;
            dto.status = rec.Status__c;
            dto.journalNumber = rec.Journal__r == null ? null : rec.Journal__r.Name;
            dto.reference = rec.Reference__c;
            rows.add(dto);
        }
        return rows;
    }

    public static List<ProjectDTO> listProjects() {
        List<ProjectDTO> rows = new List<ProjectDTO>();
        for (ERP_Project__c rec : [
            SELECT Id, Name, Project_Code__c, Billing_Method__c, Description__c, Cost_Budget__c, Revenue_Budget__c,
                   Users_JSON__c, Status__c, Customer__r.Name,
                   (SELECT Id, Name, Description__c, Billable__c FROM Project_Tasks__r)
            FROM ERP_Project__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            ProjectDTO dto = new ProjectDTO();
            dto.id = rec.Id;
            dto.projectName = rec.Name;
            dto.projectCode = rec.Project_Code__c;
            dto.customer = rec.Customer__r == null ? null : rec.Customer__r.Name;
            dto.billingMethod = rec.Billing_Method__c;
            dto.description = rec.Description__c;
            dto.costBudget = rec.Cost_Budget__c;
            dto.revenueBudget = rec.Revenue_Budget__c;
            dto.status = rec.Status__c;
            dto.users = rec.Users_JSON__c;
            dto.tasks = new List<TaskDTO>();
            for (ERP_Project_Task__c task : rec.Project_Tasks__r) {
                TaskDTO row = new TaskDTO();
                row.key = task.Id;
                row.name = task.Name;
                row.description = task.Description__c;
                row.billable = task.Billable__c;
                dto.tasks.add(row);
            }
            rows.add(dto);
        }
        return rows;
    }

    public static List<TimesheetDTO> listTimesheets() {
        List<TimesheetDTO> rows = new List<TimesheetDTO>();
        for (ERP_Timesheet__c rec : [
            SELECT Id, Name, Worker_Name__c, Project_Name__c, Hours__c, Work_Date__c, Status__c, Project__r.Name
            FROM ERP_Timesheet__c
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            TimesheetDTO dto = new TimesheetDTO();
            dto.id = rec.Id;
            dto.entryNumber = rec.Name;
            dto.staff = rec.Worker_Name__c;
            dto.job = firstNonBlank(rec.Project__r == null ? null : rec.Project__r.Name, rec.Project_Name__c);
            dto.hours = rec.Hours__c;
            dto.entryDate = rec.Work_Date__c == null ? null : String.valueOf(rec.Work_Date__c);
            dto.status = rec.Status__c;
            rows.add(dto);
        }
        return rows;
    }

    private static ERP_Journal__c loadJournal(String recordId, String journalNumber) {
        Id existing = asId(recordId);
        if (existing != null) {
            return new ERP_Journal__c(Id = existing);
        }
        List<ERP_Journal__c> found = [SELECT Id FROM ERP_Journal__c WHERE Name = :journalNumber WITH SYSTEM_MODE LIMIT 1];
        return found.isEmpty() ? new ERP_Journal__c() : new ERP_Journal__c(Id = found[0].Id);
    }

    private static Id findCustomer(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        List<ERP_Customer__c> rows = [
            SELECT Id FROM ERP_Customer__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id findDocument(String docNumber) {
        if (String.isBlank(docNumber)) {
            return null;
        }
        String key = docNumber.startsWith('doc:') ? docNumber.substring(4) : docNumber;
        List<ERP_Document__c> rows = [
            SELECT Id FROM ERP_Document__c WHERE Name = :key WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id findJournal(String journalNumber) {
        if (String.isBlank(journalNumber)) {
            return null;
        }
        List<ERP_Journal__c> rows = [
            SELECT Id FROM ERP_Journal__c WHERE Name = :journalNumber WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id findProject(String name) {
        if (String.isBlank(name)) {
            return null;
        }
        List<ERP_Project__c> rows = [
            SELECT Id FROM ERP_Project__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static Id projectCustomer(Id projectId) {
        if (projectId == null) {
            return null;
        }
        List<ERP_Project__c> rows = [
            SELECT Customer__c FROM ERP_Project__c WHERE Id = :projectId WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Customer__c;
    }

    private static Map<String, Id> customersByName(Set<String> names) {
        Map<String, Id> ids = new Map<String, Id>();
        if (names == null || names.isEmpty()) {
            return ids;
        }
        for (ERP_Customer__c row : [
            SELECT Id, Name FROM ERP_Customer__c WHERE Name IN :names WITH SYSTEM_MODE
        ]) {
            ids.put(row.Name, row.Id);
        }
        return ids;
    }

    private static Map<String, Id> ensureLedgers(Set<String> labels) {
        Map<String, Id> ids = new Map<String, Id>();
        if (labels == null || labels.isEmpty()) {
            return ids;
        }
        Map<String, String> codeByLabel = new Map<String, String>();
        Map<String, String> nameByLabel = new Map<String, String>();
        Set<String> codes = new Set<String>();
        Set<String> names = new Set<String>();
        for (String label : labels) {
            if (String.isBlank(label)) {
                continue;
            }
            String name = label.trim();
            String code = null;
            Matcher matcher = Pattern.compile('^(\\d[A-Za-z0-9\\-]{0,15})\\s+(.+)$').matcher(name);
            if (matcher.matches()) {
                code = clip(matcher.group(1), 16);
                name = matcher.group(2);
            }
            name = clip(name, 80);
            codeByLabel.put(label, code);
            nameByLabel.put(label, name);
            if (String.isNotBlank(code)) {
                codes.add(code);
            }
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }
        Map<String, Id> idByCode = new Map<String, Id>();
        Map<String, Id> idByName = new Map<String, Id>();
        if (!codes.isEmpty()) {
            for (ERP_Ledger__c row : [
                SELECT Id, Code__c FROM ERP_Ledger__c WHERE Code__c IN :codes WITH SYSTEM_MODE
            ]) {
                idByCode.put(row.Code__c, row.Id);
            }
        }
        if (!names.isEmpty()) {
            for (ERP_Ledger__c row : [
                SELECT Id, Name FROM ERP_Ledger__c WHERE Name IN :names WITH SYSTEM_MODE
            ]) {
                idByName.put(row.Name, row.Id);
            }
        }
        List<ERP_Ledger__c> fresh = new List<ERP_Ledger__c>();
        Set<String> queuedCodes = new Set<String>();
        Set<String> queuedNames = new Set<String>();
        for (String label : labels) {
            String code = codeByLabel.get(label);
            String name = nameByLabel.get(label);
            if (String.isBlank(name)) {
                continue;
            }
            if (String.isNotBlank(code) && idByCode.containsKey(code)) {
                continue;
            }
            if (idByName.containsKey(name) || queuedNames.contains(name) || (String.isNotBlank(code) && queuedCodes.contains(code))) {
                continue;
            }
            fresh.add(new ERP_Ledger__c(
                Name = name,
                Code__c = code,
                Kind__c = 'posting',
                Active__c = true
            ));
            queuedNames.add(name);
            if (String.isNotBlank(code)) {
                queuedCodes.add(code);
            }
        }
        if (!fresh.isEmpty()) {
            Database.insert(fresh, AccessLevel.SYSTEM_MODE);
            for (ERP_Ledger__c row : fresh) {
                if (String.isNotBlank(row.Code__c)) {
                    idByCode.put(row.Code__c, row.Id);
                }
                idByName.put(row.Name, row.Id);
            }
        }
        for (String label : labels) {
            String code = codeByLabel.get(label);
            String name = nameByLabel.get(label);
            Id ledgerId = String.isNotBlank(code) ? idByCode.get(code) : null;
            if (ledgerId == null) {
                ledgerId = idByName.get(name);
            }
            ids.put(label, ledgerId);
        }
        return ids;
    }

    public static Id ensureLedger(String label) {
        if (String.isBlank(label)) {
            return null;
        }
        String code = null;
        String name = label.trim();
        Matcher m = Pattern.compile('^(\\d[A-Za-z0-9\\-]{0,15})\\s+(.+)$').matcher(name);
        if (m.matches()) {
            code = clip(m.group(1), 16);
            name = m.group(2);
        }
        name = clip(name, 80);
        if (String.isNotBlank(code)) {
            List<ERP_Ledger__c> byCode = [
                SELECT Id FROM ERP_Ledger__c WHERE Code__c = :code WITH SYSTEM_MODE LIMIT 1
            ];
            if (!byCode.isEmpty()) {
                return byCode[0].Id;
            }
        }
        List<ERP_Ledger__c> byName = [
            SELECT Id FROM ERP_Ledger__c WHERE Name = :name WITH SYSTEM_MODE LIMIT 1
        ];
        if (!byName.isEmpty()) {
            return byName[0].Id;
        }
        ERP_Ledger__c rec = new ERP_Ledger__c(
            Name = name,
            Code__c = code,
            Kind__c = 'posting',
            Active__c = true
        );
        Database.insert(rec, AccessLevel.SYSTEM_MODE);
        return rec.Id;
    }

    private static String ledgerLabel(ERP_Ledger__c rec) {
        if (rec == null) {
            return '';
        }
        return String.isBlank(rec.Code__c) ? rec.Name : rec.Code__c + ' ' + rec.Name;
    }

    private static String paymentType(String kind) {
        String value = defaultText(kind, '');
        if (value.containsIgnoreCase('advance')) {
            return 'Vendor Advance';
        }
        if (value.containsIgnoreCase('receipt')) {
            return 'Receipt';
        }
        if (value.containsIgnoreCase('payout')) {
            return 'Payout';
        }
        return 'Vendor Payment';
    }

    private static String firstParty(Map<String, Object> payload) {
        for (Object raw : listValue(payload.get('lines'))) {
            Map<String, Object> line = (Map<String, Object>) raw;
            String party = textValue(line.get('party'));
            if (String.isNotBlank(party)) {
                return party;
            }
        }
        return null;
    }

    private static String firstBill(String value) {
        if (String.isBlank(value) || value == 'Advance') {
            return null;
        }
        return value.split(',')[0].trim();
    }

    private static String lineJson(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            return (String) value;
        }
        return JSON.serialize(value);
    }

    private static List<Object> listValue(Object value) {
        if (value instanceof List<Object>) {
            return (List<Object>) value;
        }
        return new List<Object>();
    }

    private static Map<String, Object> readPayload(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        return (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
    }

    private static Id asId(String value) {
        if (String.isBlank(value) || value.contains('-')) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String pick(String value, Set<String> allowed, String fallback) {
        return allowed.contains(value) ? value : fallback;
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
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

    private static String clip(String value, Integer max) {
        if (value == null) {
            return null;
        }
        return value.length() <= max ? value : value.substring(0, max);
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