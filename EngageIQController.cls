public with sharing class EngageIQController {
    static AuraHandledException handled(String message) {
        String text = String.isBlank(message) ? 'Request failed.' : message.left(1000);
        AuraHandledException ex = new AuraHandledException(text);
        ex.setMessage(text);
        return ex;
    }

    @AuraEnabled
    public static Map<String, Object> loadHome(Id websiteId) {
        try {
            return EngageIQService.loadHome(websiteId);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> listWebsites() {
        try {
            return EngageIQService.listWebsites();
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> saveWebsite(Id websiteId, String name, String domain, String status) {
        try {
            return EngageIQService.saveWebsite(websiteId, name, domain, status);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> setWebsiteStatus(Id websiteId, String status) {
        try {
            return EngageIQService.setWebsiteStatus(websiteId, status);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> saveBrandColor(String brandColor) {
        try {
            return EngageIQService.saveBrandColor(brandColor);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> loadInbox(Id conversationId) {
        try {
            return EngageIQService.loadInbox(conversationId);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> sendAgentMessage(Id conversationId, String body) {
        try {
            if (conversationId == null || String.isBlank(body)) {
                throw new EngageIQService.ApiException('Conversation and message are required');
            }
            String payload = JSON.serialize(
                new Map<String, Object>{ 'transcriptId' => conversationId, 'body' => body }
            );
            EngageIQService.postMessage(payload, 'Agent', UserInfo.getUserId());
            return EngageIQService.loadInbox(conversationId);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> assignToMe(Id conversationId) {
        try {
            return EngageIQService.assignToMe(conversationId);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> closeConversation(Id conversationId) {
        try {
            return EngageIQService.closeConversation(conversationId);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> captureLead(
        Id conversationId,
        Id visitorId,
        String fullName,
        String email,
        String phone,
        String company
    ) {
        try {
            Map<String, Object> payload = new Map<String, Object>{
                'name' => fullName,
                'email' => email,
                'phone' => phone,
                'company' => company
            };
            if (conversationId != null) {
                payload.put('transcriptId', conversationId);
            }
            if (visitorId != null) {
                payload.put('visitorId', visitorId);
            }
            EngageIQService.captureLead(JSON.serialize(payload));
            if (conversationId != null) {
                return EngageIQService.loadInbox(conversationId);
            }
            return EngageIQService.loadHome(null);
        } catch (Exception e) {
            throw handled(e.getMessage());
        }
    }
}