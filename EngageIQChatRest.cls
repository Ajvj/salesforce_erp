@RestResource(urlMapping='/chat/*')
global without sharing class EngageIQChatRest {
    @HttpPost
    global static void doPost() {
        EngageIQRestUtil.cors();
        try {
            String path = EngageIQRestUtil.path(RestContext.request, '/chat/');
            String body = EngageIQRestUtil.body();
            if (path == 'start') {
                EngageIQRestUtil.write(200, EngageIQService.startChat(body));
                return;
            }
            if (path == 'message') {
                EngageIQRestUtil.write(200, EngageIQService.postMessage(body, 'Visitor', null));
                return;
            }
            if (path == 'lead') {
                EngageIQRestUtil.write(200, EngageIQService.captureLead(body));
                return;
            }
            EngageIQRestUtil.write(404, new Map<String, String>{ 'error' => 'Unknown chat route' });
        } catch (Exception e) {
            EngageIQRestUtil.write(400, new Map<String, String>{ 'error' => e.getMessage() });
        }
    }

    @HttpGet
    global static void doGet() {
        EngageIQRestUtil.cors();
        try {
            String path = EngageIQRestUtil.path(RestContext.request, '/chat/');
            if (path == 'messages' || path.startsWith('messages')) {
                String transcriptId = RestContext.request.params.get('transcriptId');
                String afterId = RestContext.request.params.get('afterId');
                if (String.isBlank(transcriptId)) {
                    throw new EngageIQService.ApiException('transcriptId is required');
                }
                EngageIQRestUtil.write(200, EngageIQService.listMessages((Id) transcriptId, afterId));
                return;
            }
            EngageIQRestUtil.write(404, new Map<String, String>{ 'error' => 'Unknown chat route' });
        } catch (Exception e) {
            EngageIQRestUtil.write(400, new Map<String, String>{ 'error' => e.getMessage() });
        }
    }
}