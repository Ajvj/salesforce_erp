@RestResource(urlMapping='/visitor/*')
global without sharing class EngageIQVisitorRest {
    @HttpPost
    global static void doPost() {
        EngageIQRestUtil.cors();
        try {
            String path = EngageIQRestUtil.path(RestContext.request, '/visitor/');
            String body = EngageIQRestUtil.body();
            if (path == 'track' || path == '' || path == 'heartbeat') {
                EngageIQRestUtil.write(200, EngageIQService.track(body));
                return;
            }
            EngageIQRestUtil.write(404, new Map<String, String>{ 'error' => 'Unknown visitor route' });
        } catch (Exception e) {
            EngageIQRestUtil.write(400, new Map<String, String>{ 'error' => e.getMessage() });
        }
    }

    @HttpGet
    global static void doGet() {
        EngageIQRestUtil.cors();
        EngageIQRestUtil.write(200, new Map<String, String>{ 'status' => 'ok', 'service' => 'EngageIQ' });
    }
}