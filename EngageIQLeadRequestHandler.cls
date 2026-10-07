public without sharing class EngageIQLeadRequestHandler {
    public static void handle(List<EngageIQ_Lead_Request__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        Set<Id> visitorIds = new Set<Id>();
        for (EngageIQ_Lead_Request__e event : events) {
            if (String.isNotBlank(event.Visitor_Id__c)) {
                visitorIds.add((Id) event.Visitor_Id__c);
            }
        }
        Map<Id, EngageIQ_Visitor__c> visitors = new Map<Id, EngageIQ_Visitor__c>([
            SELECT Id, Full_Name__c, Email__c, Phone__c, Company__c, Lead__c, IP_Address__c, City__c, Region__c, Country__c
            FROM EngageIQ_Visitor__c
            WHERE Id IN :visitorIds
            WITH SYSTEM_MODE
        ]);
        for (EngageIQ_Lead_Request__e event : events) {
            if (String.isBlank(event.Visitor_Id__c) || !visitors.containsKey((Id) event.Visitor_Id__c)) {
                continue;
            }
            EngageIQ_Visitor__c visitor = visitors.get((Id) event.Visitor_Id__c);
            String fullName = String.isBlank(event.Full_Name__c) ? visitor.Full_Name__c : event.Full_Name__c;
            String firstName;
            String lastName = 'Website visitor';
            if (String.isNotBlank(fullName)) {
                List<String> parts = fullName.normalizeSpace().split(' ', 2);
                if (parts.size() == 1) {
                    lastName = parts[0];
                } else {
                    firstName = parts[0];
                    lastName = parts[1];
                }
            }
            String company = String.isBlank(event.Company__c)
                ? (String.isBlank(visitor.Company__c) ? 'EngageIQ Chat' : visitor.Company__c)
                : event.Company__c;
            String email = String.isBlank(event.Email__c) ? visitor.Email__c : event.Email__c;
            String phone = String.isBlank(event.Phone__c) ? visitor.Phone__c : event.Phone__c;
            List<String> loc = new List<String>();
            if (String.isNotBlank(visitor.City__c)) {
                loc.add(visitor.City__c);
            }
            if (String.isNotBlank(visitor.Region__c)) {
                loc.add(visitor.Region__c);
            }
            if (String.isNotBlank(visitor.Country__c)) {
                loc.add(visitor.Country__c);
            }
            String description =
                'Converted from EngageIQ by Community Plus user. IP: ' +
                (visitor.IP_Address__c == null ? 'unknown' : visitor.IP_Address__c) +
                '. Location: ' +
                (loc.isEmpty() ? 'unknown' : String.join(loc, ', '));
            Lead leadRec;
            if (visitor.Lead__c != null) {
                leadRec = new Lead(
                    Id = visitor.Lead__c,
                    FirstName = firstName,
                    LastName = lastName,
                    Email = email,
                    Phone = phone,
                    Company = company,
                    Description = description
                );
                Database.update(leadRec, AccessLevel.SYSTEM_MODE);
            } else {
                leadRec = new Lead(
                    FirstName = firstName,
                    LastName = lastName,
                    Email = email,
                    Phone = phone,
                    Company = company,
                    LeadSource = 'EngageIQ',
                    Description = description
                );
                Database.insert(leadRec, AccessLevel.SYSTEM_MODE);
            }
            visitor.Lead__c = leadRec.Id;
            visitor.Status__c = 'Converted';
            visitor.Full_Name__c = fullName;
            visitor.Email__c = email;
            visitor.Phone__c = phone;
            visitor.Company__c = company;
            Database.update(visitor, AccessLevel.SYSTEM_MODE);
            if (String.isNotBlank(event.Conversation_Id__c)) {
                Database.update(
                    new EngageIQ_Conversation__c(
                        Id = (Id) event.Conversation_Id__c,
                        Lead__c = leadRec.Id,
                        Visitor_Name__c = fullName
                    ),
                    AccessLevel.SYSTEM_MODE
                );
            }
        }
    }
}