@IsTest
private class ERPBooksControllerTest {
    @IsTest
    static void coversBooksSaveAndList() {
        ERP_Customer__c party = new ERP_Customer__c(Name = 'Nila Supplies', Status__c = 'Active');
        insert party;
        ERP_Document__c bill = new ERP_Document__c(
            Name = 'BILL-00001',
            Document_Type__c = 'Vendor Bill',
            Customer_Name__c = 'Nila Supplies',
            Total__c = 1000,
            Status__c = 'Sent'
        );
        insert bill;

        Id journalId = ERPBooksController.saveJournal(
            JSON.serialize(new Map<String, Object>{
                'journalNumber' => 'JV-00001',
                'journalDate' => String.valueOf(Date.today()),
                'journalNarration' => 'Expense EXP-00001',
                'journalBasis' => 'cash',
                'status' => 'Posted',
                'total' => 250,
                'lines' => new List<Object>{
                    new Map<String, Object>{ 'ledger' => '610000 People cost', 'debit' => 250, 'credit' => 0, 'party' => 'Nila Supplies', 'particulars' => 'EXP-00001' },
                    new Map<String, Object>{ 'ledger' => '111100 Cash on hand', 'debit' => 0, 'credit' => 250, 'party' => 'Nila Supplies', 'particulars' => 'EXP-00001' }
                }
            })
        );
        System.assertNotEquals(null, journalId);

        Id expenseId = ERPBooksController.saveExpense(
            JSON.serialize(new Map<String, Object>{
                'number' => 'EXP-00001',
                'kind' => 'expense',
                'date' => String.valueOf(Date.today()),
                'account' => '610000 People cost',
                'amount' => 250,
                'paidThrough' => '111100 Cash on hand',
                'vendor' => 'Nila Supplies',
                'journalNumber' => 'JV-00001',
                'status' => 'Posted'
            })
        );
        System.assertNotEquals(null, expenseId);

        Id recExpId = ERPBooksController.saveRecurringExpense(
            JSON.serialize(new Map<String, Object>{
                'profileName' => 'Rent',
                'repeatEvery' => 'Month',
                'startDate' => String.valueOf(Date.today()),
                'expenseAccount' => '620000 Rent and occupancy',
                'amount' => 1000,
                'paidThrough' => '111200 Operating bank book',
                'vendor' => 'Nila Supplies',
                'neverExpires' => true
            })
        );
        System.assertNotEquals(null, recExpId);

        Id recBillId = ERPBooksController.saveRecurringBill(
            JSON.serialize(new Map<String, Object>{
                'profileName' => 'Monthly supplies',
                'vendor' => 'Nila Supplies',
                'repeatEvery' => 'Month',
                'startDate' => String.valueOf(Date.today()),
                'amount' => 500,
                'lines' => new List<Object>{ new Map<String, Object>{ 'details' => 'Spare pack', 'qty' => 1, 'rate' => 500 } }
            })
        );
        System.assertNotEquals(null, recBillId);

        Id payId = ERPBooksController.savePayment(
            JSON.serialize(new Map<String, Object>{
                'paymentNumber' => 'PAY-00001',
                'kind' => 'Bill Payment',
                'vendor' => 'Nila Supplies',
                'amount' => 1000,
                'bill' => 'BILL-00001',
                'paymentDate' => String.valueOf(Date.today()),
                'paymentMode' => 'Cash',
                'paidThrough' => '111100 Cash on hand',
                'journalNumber' => 'JV-00001',
                'status' => 'Paid'
            })
        );
        System.assertNotEquals(null, payId);

        Id projectId = ERPBooksController.saveProject(
            JSON.serialize(new Map<String, Object>{
                'projectName' => 'Acme handover',
                'customer' => 'Nila Supplies',
                'billingMethod' => 'Based on Project Hours',
                'costBudget' => 1000,
                'revenueBudget' => 2000,
                'users' => new List<Object>{ new Map<String, Object>{ 'name' => 'Priya', 'email' => 'priya@example.com' } },
                'tasks' => new List<Object>{ new Map<String, Object>{ 'name' => 'Install', 'description' => 'On site', 'billable' => true } }
            })
        );
        System.assertNotEquals(null, projectId);

        Id timeId = ERPBooksController.saveTimesheet(
            JSON.serialize(new Map<String, Object>{
                'number' => 'TS-00001',
                'staff' => 'Priya Nair',
                'job' => 'Acme handover',
                'hours' => 4,
                'date' => String.valueOf(Date.today()),
                'status' => 'Billable'
            })
        );
        System.assertNotEquals(null, timeId);

        ERPBooksController.BooksDTO books = ERPBooksController.getBooks();
        System.assertEquals(1, books.journals.size());
        System.assertEquals(2, books.journals[0].lines.size());
        System.assertEquals(1, books.expenses.size());
        System.assertEquals(expenseId, books.expenses[0].id);
        System.assertEquals('JV-00001', books.expenses[0].journalNumber);
        System.assertEquals(1, books.recurringExpenses.size());
        System.assertEquals(1, books.recurringBills.size());
        System.assertEquals(1, books.paymentsMade.size());
        System.assertEquals('BILL-00001', books.paymentsMade[0].bill);
        System.assertEquals(1, books.projects.size());
        System.assertEquals(1, books.projects[0].tasks.size());
        System.assertEquals(1, books.timesheets.size());
        System.assertEquals(projectId, [
            SELECT Project__c FROM ERP_Timesheet__c WHERE Id = :timeId
        ].Project__c);
    }
}