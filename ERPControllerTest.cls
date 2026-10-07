@IsTest
private class ERPControllerTest {
    @IsTest
    static void coversSaveListAndDelete() {
        Id itemId = ERPController.saveItem(
            JSON.serialize(new Map<String, Object>{
                'name' => 'Widget',
                'itemType' => 'Goods',
                'unit' => 'pcs',
                'sellingPrice' => 100,
                'salesAccount' => 'Sales',
                'costPrice' => 40,
                'purchaseAccount' => 'Cost of Goods Sold',
                'salesEnabled' => true,
                'purchaseEnabled' => true
            }),
            false
        );
        System.assertNotEquals(null, itemId);

        Id draftItemId = ERPController.saveItem(JSON.serialize(new Map<String, Object>()), true);
        System.assertNotEquals(null, draftItemId);

        Id customerId = ERPController.saveCustomer(
            JSON.serialize(new Map<String, Object>{
                'displayName' => 'Acme',
                'customerType' => 'Business',
                'billingCity' => 'Chennai'
            }),
            false
        );
        System.assertNotEquals(null, customerId);

        Id quoteId = ERPController.saveDocument(
            JSON.serialize(new Map<String, Object>{
                'documentType' => 'Quote',
                'customerName' => 'Acme',
                'documentNumber' => 'QT-00001',
                'lineItemsJson' => '[]',
                'subTotal' => 0,
                'totalAmount' => 0
            }),
            false
        );
        System.assertNotEquals(null, quoteId);

        ERPController.BootstrapDTO data = ERPController.getBootstrap();
        System.assertEquals(2, data.items.size());
        System.assertEquals(1, data.customers.size());
        System.assertEquals(1, data.documents.size());
        System.assertNotEquals(null, data.insights);
        ERPAiService.ResultDTO ai = ERPController.runAi('dashboard', '{}');
        System.assertNotEquals(null, ai);
        System.assertNotEquals(null, ERPController.runAi('itemSku', JSON.serialize(new Map<String, Object>{ 'name' => 'Widget', 'itemType' => 'Goods' })));
        System.assertNotEquals(null, ERPController.runAi('itemSalesDescription', JSON.serialize(new Map<String, Object>{ 'name' => 'Widget' })));
        System.assertNotEquals(null, ERPController.runAi('itemPurchaseDescription', JSON.serialize(new Map<String, Object>{ 'name' => 'Widget' })));
        System.assertNotEquals(null, ERPController.runAi('customerCredit', JSON.serialize(new Map<String, Object>{ 'displayName' => 'Acme', 'gstin' => '33AABCU9603R1ZM' })));
        System.assertNotEquals(null, ERPController.runAi('suggestLines', '{}'));
        System.assertNotEquals(null, ERPController.runAi('documentSubject', JSON.serialize(new Map<String, Object>{ 'customerName' => 'Acme' })));
        System.assertNotEquals(null, ERPController.runAi('documentNotes', JSON.serialize(new Map<String, Object>{ 'customerName' => 'Acme' })));
        System.assertNotEquals(null, ERPController.runAi('documentTerms', '{}'));
        System.assertNotEquals(null, ERPController.runAi('documentEmail', JSON.serialize(new Map<String, Object>{ 'customerName' => 'Acme' })));
        System.assertNotEquals(null, ERPController.runAi('documentReview', JSON.serialize(new Map<String, Object>{ 'customerName' => 'Acme', 'totalAmount' => 100, 'lineItems' => new List<Object>() })));
        ERPAiService.ResultDTO translated = ERPController.runAi(
            'walkthroughTranslate',
            JSON.serialize(new Map<String, Object>{
                'languageName' => 'Hindi',
                'languageCode' => 'hi-IN',
                'scenesJson' => '[{"title":"Open","caption":"Go to Sales Orders","mock":"All Sales Orders","voice":"Welcome"}]'
            })
        );
        System.assertNotEquals(null, translated);
        System.assertNotEquals(null, translated.text);

        ERPController.deleteDocument(quoteId);
        ERPController.deleteCustomer(customerId);
        ERPController.deleteItem(itemId);
        ERPController.deleteItem(draftItemId);
        System.assertEquals(0, ERPController.listItems().size());

        ERPController.IdentityScanDTO scan = ERPController.readIdentityScan(
            'GSTIN-PAN.pdf',
            EncodingUtil.base64Encode(Blob.valueOf('GSTIN 33AABCU9603R1ZM Legal Name Acme Traders PAN AABCU9603R Chennai 600001'))
        );
        System.assertEquals('33AABCU9603R1ZM', scan.gstin);
        System.assertEquals('AABCU9603R', scan.pan);

        ERPController.EmailResultDTO mailed = ERPController.sendVoucherEmail(
            JSON.serialize(new Map<String, Object>{
                'toAddress' => 'accounts@example.com',
                'subject' => 'Journal voucher JV-00001',
                'htmlBody' => '<p>Journal voucher JV-00001</p>',
                'plainBody' => 'Journal voucher JV-00001'
            })
        );
        System.assertEquals(true, mailed.sent);
        System.assertEquals('accounts@example.com', mailed.toAddress);
    }
}