public without sharing class EngageIQService {
    public class ApiException extends Exception {
    }

    static Id ownerId() {
        EngageIQ_Config__mdt cfg = EngageIQ_Config__mdt.getInstance('Default');
        if (cfg != null && String.isNotBlank(cfg.Default_Owner_Username__c)) {
            List<User> found = [
                SELECT Id
                FROM User
                WHERE Username = :cfg.Default_Owner_Username__c AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!found.isEmpty()) {
                return found[0].Id;
            }
        }
        return UserInfo.getUserId();
    }

    static String widgetBaseUrl() {
        EngageIQ_Config__mdt cfg = EngageIQ_Config__mdt.getInstance('Default');
        if (cfg != null && String.isNotBlank(cfg.Widget_Base_Url__c)) {
            return cfg.Widget_Base_Url__c.replaceAll('/$', '');
        }
        return 'https://orgfarm-b36ec4029b-dev-ed.develop.my.site.com/engage';
    }

    public static final String DEFAULT_BRAND_COLOR = '#3d1466';

    public static String brandColor() {
        EngageIQ_Theme__c theme = EngageIQ_Theme__c.getOrgDefaults();
        if (theme != null && String.isNotBlank(theme.Brand_Color__c)) {
            String fromTheme = normalizeHexColor(theme.Brand_Color__c);
            if (fromTheme != null) {
                return fromTheme;
            }
        }
        EngageIQ_Config__mdt cfg = EngageIQ_Config__mdt.getInstance('Default');
        if (cfg != null && String.isNotBlank(cfg.Brand_Color__c)) {
            String hex = normalizeHexColor(cfg.Brand_Color__c);
            if (hex != null) {
                return hex;
            }
        }
        return DEFAULT_BRAND_COLOR;
    }

    public static String normalizeHexColor(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String t = raw.trim();
        if (!t.startsWith('#')) {
            t = '#' + t;
        }
        t = t.toLowerCase();
        Matcher three = Pattern.compile('^#([0-9a-f])([0-9a-f])([0-9a-f])$').matcher(t);
        if (three.matches()) {
            return '#' + three.group(1) + three.group(1) + three.group(2) + three.group(2) + three.group(3) + three.group(3);
        }
        Matcher six = Pattern.compile('^#([0-9a-f]{6})$').matcher(t);
        if (six.matches()) {
            return t;
        }
        return null;
    }

    static Map<String, Object> themePayload() {
        return new Map<String, Object>{ 'brandColor' => brandColor() };
    }

    public static Map<String, Object> saveBrandColor(String color) {
        String hex = normalizeHexColor(color);
        if (hex == null) {
            throw new ApiException('Use a hex colour such as #3d1466');
        }
        EngageIQ_Theme__c theme = EngageIQ_Theme__c.getOrgDefaults();
        theme.Brand_Color__c = hex;
        Database.upsert(theme, AccessLevel.SYSTEM_MODE);
        Map<String, Object> payload = listWebsites();
        payload.put('brandColor', hex);
        return payload;
    }

    public static String normalizeHost(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String t = raw.trim().toLowerCase();
        if (t.startsWith('https://')) {
            t = t.substring(8);
        } else if (t.startsWith('http://')) {
            t = t.substring(7);
        }
        Integer slash = t.indexOf('/');
        if (slash >= 0) {
            t = t.substring(0, slash);
        }
        Integer colon = t.indexOf(':');
        if (colon >= 0) {
            t = t.substring(0, colon);
        }
        if (t.startsWith('www.')) {
            t = t.substring(4);
        }
        return String.isBlank(t) ? null : t;
    }

    static String newSiteKey() {
        return 'eiq_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
    }

    static String embedSnippet(EngageIQ_Website__c site) {
        if (site == null || String.isBlank(site.Site_Key__c)) {
            return null;
        }
        String base = widgetBaseUrl();
        return '<script>\n' +
            '  window.SF_CHAT_CONFIG = {\n' +
            '    baseUrl: "' +
            base +
            '",\n' +
            '    siteKey: "' +
            site.Site_Key__c +
            '"\n' +
            '  };\n' +
            '</script>\n' +
            '<script src="' +
            base +
            '/s/sfsites/c/resource/EngageIQ_Widget" async></script>';
    }

    static Map<String, Object> websitePayload(EngageIQ_Website__c row) {
        Map<String, Object> payload = toMap(row);
        payload.put('embedSnippet', embedSnippet(row));
        payload.put('widgetSrc', widgetBaseUrl() + '/s/sfsites/c/resource/EngageIQ_Widget');
        payload.put('widgetBaseUrl', widgetBaseUrl());
        return payload;
    }

    static EngageIQ_Website__c resolveWebsite(Map<String, Object> data) {
        String siteKey = str(data, 'siteKey');
        if (String.isNotBlank(siteKey)) {
            List<EngageIQ_Website__c> keyed = [
                SELECT Id, Name, Domain__c, Normalized_Domain__c, Site_Key__c, Status__c
                FROM EngageIQ_Website__c
                WHERE Site_Key__c = :siteKey AND Status__c = 'Active'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return keyed.isEmpty() ? null : keyed[0];
        }
        String host = normalizeHost(str(data, 'pageUrl'));
        if (String.isBlank(host)) {
            return null;
        }
        List<EngageIQ_Website__c> byHost = [
            SELECT Id, Name, Domain__c, Normalized_Domain__c, Site_Key__c, Status__c
            FROM EngageIQ_Website__c
            WHERE Normalized_Domain__c = :host AND Status__c = 'Active'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return byHost.isEmpty() ? null : byHost[0];
    }

    public static Map<String, Object> listWebsites() {
        List<EngageIQ_Website__c> rows = [
            SELECT Id, Name, Domain__c, Normalized_Domain__c, Site_Key__c, Status__c, CreatedDate, LastModifiedDate
            FROM EngageIQ_Website__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 200
        ];
        List<Map<String, Object>> items = new List<Map<String, Object>>();
        Integer activeCount = 0;
        for (EngageIQ_Website__c row : rows) {
            items.add(websitePayload(row));
            if (row.Status__c == 'Active') {
                activeCount++;
            }
        }
        Map<String, Object> payload = new Map<String, Object>{
            'websites' => items,
            'websiteCount' => rows.size(),
            'activeCount' => activeCount,
            'inactiveCount' => rows.size() - activeCount,
            'widgetBaseUrl' => widgetBaseUrl()
        };
        payload.putAll(themePayload());
        return payload;
    }

    public static Map<String, Object> saveWebsite(Id websiteId, String name, String domain, String status) {
        String trimmedName = name == null ? null : name.trim();
        String displayDomain = domain == null ? null : domain.trim();
        String host = normalizeHost(displayDomain);
        if (String.isBlank(trimmedName)) {
            throw new ApiException('Website name is required');
        }
        if (String.isBlank(host)) {
            throw new ApiException('Website domain is required, for example www.bank.com');
        }
        String nextStatus = String.isBlank(status) ? 'Active' : status;
        if (nextStatus != 'Active' && nextStatus != 'Inactive') {
            throw new ApiException('Status must be Active or Inactive');
        }
        List<EngageIQ_Website__c> clash;
        if (websiteId == null) {
            clash = [
                SELECT Id
                FROM EngageIQ_Website__c
                WHERE Normalized_Domain__c = :host
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } else {
            clash = [
                SELECT Id
                FROM EngageIQ_Website__c
                WHERE Normalized_Domain__c = :host AND Id != :websiteId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        }
        if (!clash.isEmpty()) {
            throw new ApiException('That domain is already registered as another website');
        }
        EngageIQ_Website__c row;
        if (websiteId == null) {
            row = new EngageIQ_Website__c(
                Name = clip(trimmedName, 80),
                Domain__c = clip(displayDomain, 255),
                Normalized_Domain__c = host,
                Site_Key__c = newSiteKey(),
                Status__c = nextStatus,
                OwnerId = ownerId()
            );
            insertSys(row);
        } else {
            row = [
                SELECT Id, Name, Domain__c, Normalized_Domain__c, Site_Key__c, Status__c
                FROM EngageIQ_Website__c
                WHERE Id = :websiteId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            row.Name = clip(trimmedName, 80);
            row.Domain__c = clip(displayDomain, 255);
            row.Normalized_Domain__c = host;
            row.Status__c = nextStatus;
            updateSys(row);
        }
        Map<String, Object> payload = listWebsites();
        payload.put('website', websitePayload(row));
        return payload;
    }

    public static Map<String, Object> setWebsiteStatus(Id websiteId, String status) {
        if (websiteId == null) {
            throw new ApiException('Website is required');
        }
        EngageIQ_Website__c row = [
            SELECT Id, Name, Domain__c
            FROM EngageIQ_Website__c
            WHERE Id = :websiteId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return saveWebsite(websiteId, row.Name, row.Domain__c, status);
    }

    static String clip(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLen ? value : value.left(maxLen);
    }

    static void insertSys(SObject rec) {
        Database.insert(rec, AccessLevel.SYSTEM_MODE);
    }

    static void updateSys(SObject rec) {
        Database.update(rec, AccessLevel.SYSTEM_MODE);
    }

    static Map<String, Object> asMap(String body) {
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        Object parsed = JSON.deserializeUntyped(body);
        if (parsed instanceof Map<String, Object>) {
            return (Map<String, Object>) parsed;
        }
        return new Map<String, Object>();
    }

    static String str(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) {
            return null;
        }
        String value = String.valueOf(data.get(key)).trim();
        if (value == 'null' || value == 'undefined' || value == '') {
            return null;
        }
        return value;
    }

    static String firstNonBlank(List<String> values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return null;
    }

    static String header(String name) {
        if (RestContext.request == null || RestContext.request.headers == null) {
            return null;
        }
        return RestContext.request.headers.get(name);
    }

    public static String clientIp() {
        String forwarded = header('X-Forwarded-For');
        if (String.isNotBlank(forwarded)) {
            return forwarded.split(',')[0].trim();
        }
        String sip = firstNonBlank(
            new List<String>{ header('True-Client-IP'), header('X-Salesforce-SIP'), header('X-Real-IP') }
        );
        if (String.isNotBlank(sip)) {
            return sip;
        }
        return RestContext.request == null ? null : RestContext.request.remoteAddress;
    }

    static Boolean isPrivateIp(String ip) {
        if (String.isBlank(ip)) {
            return true;
        }
        return ip == '127.0.0.1' ||
            ip == '::1' ||
            ip.startsWith('10.') ||
            ip.startsWith('192.168.') ||
            ip.startsWith('127.') ||
            ip.startsWith('0.') ||
            ip.startsWith('169.254.');
    }

    static String deviceOf(String userAgent) {
        if (String.isBlank(userAgent)) {
            return 'Unknown';
        }
        String ua = userAgent.toLowerCase();
        if (ua.contains('tablet') || ua.contains('ipad')) {
            return 'Tablet';
        }
        if (ua.contains('mobi') || ua.contains('android') || ua.contains('iphone')) {
            return 'Mobile';
        }
        return 'Desktop';
    }

    @TestVisible
    static Map<String, String> lookupGeo(String ip) {
        Map<String, String> geo = new Map<String, String>();
        if (String.isBlank(ip) || isPrivateIp(ip)) {
            geo.put('country', 'Local / private network');
            geo.put('city', null);
            geo.put('region', null);
            geo.put('timezone', null);
            geo.put('isp', null);
            return geo;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://ipapi.co/' + EncodingUtil.urlEncode(ip, 'UTF-8') + '/json/');
        req.setMethod('GET');
        req.setTimeout(4000);
        req.setHeader('User-Agent', 'EngageIQ/1.0');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300 || String.isBlank(res.getBody())) {
            return geo;
        }
        Object parsed = JSON.deserializeUntyped(res.getBody());
        if (!(parsed instanceof Map<String, Object>)) {
            return geo;
        }
        Map<String, Object> data = (Map<String, Object>) parsed;
        geo.put('country', data.get('country_name') == null ? null : String.valueOf(data.get('country_name')));
        geo.put('region', data.get('region') == null ? null : String.valueOf(data.get('region')));
        geo.put('city', data.get('city') == null ? null : String.valueOf(data.get('city')));
        geo.put('timezone', data.get('timezone') == null ? null : String.valueOf(data.get('timezone')));
        geo.put('isp', data.get('org') == null ? null : String.valueOf(data.get('org')));
        if (data.get('latitude') != null) {
            geo.put('latitude', String.valueOf(data.get('latitude')));
        }
        if (data.get('longitude') != null) {
            geo.put('longitude', String.valueOf(data.get('longitude')));
        }
        return geo;
    }

    static String locationOf(EngageIQ_Visitor__c visitor) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(visitor.City__c)) {
            parts.add(visitor.City__c);
        }
        if (String.isNotBlank(visitor.Region__c)) {
            parts.add(visitor.Region__c);
        }
        if (String.isNotBlank(visitor.Country__c)) {
            parts.add(visitor.Country__c);
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    static void applyGeo(EngageIQ_Visitor__c visitor, Map<String, String> geo) {
        if (geo == null || geo.isEmpty()) {
            return;
        }
        if (geo.containsKey('country')) {
            visitor.Country__c = clip(geo.get('country'), 80);
        }
        if (geo.containsKey('region')) {
            visitor.Region__c = clip(geo.get('region'), 80);
        }
        if (geo.containsKey('city')) {
            visitor.City__c = clip(geo.get('city'), 80);
        }
        if (geo.containsKey('timezone') && String.isNotBlank(geo.get('timezone'))) {
            visitor.Timezone__c = clip(geo.get('timezone'), 80);
        }
        if (geo.containsKey('isp')) {
            visitor.ISP__c = clip(geo.get('isp'), 255);
        }
        if (String.isNotBlank(geo.get('latitude'))) {
            visitor.Latitude__c = Decimal.valueOf(geo.get('latitude'));
        }
        if (String.isNotBlank(geo.get('longitude'))) {
            visitor.Longitude__c = Decimal.valueOf(geo.get('longitude'));
        }
    }

    static void audit(
        String eventType,
        Id visitorId,
        Id conversationId,
        Id leadId,
        String actorType,
        String actorName,
        String ip,
        String location,
        String pageUrl,
        String details
    ) {
        insertSys(new EngageIQ_Audit__c(
            Event_Type__c = eventType,
            Visitor__c = visitorId,
            Conversation__c = conversationId,
            Lead__c = leadId,
            Actor_Type__c = actorType,
            Actor_Name__c = clip(actorName, 80),
            IP_Address__c = clip(ip, 45),
            Location__c = clip(location, 255),
            Page_Url__c = clip(pageUrl, 1024),
            Details__c = details,
            Occurred_At__c = System.now(),
            OwnerId = ownerId()
        ));
    }

    static EngageIQ_Visitor__c upsertVisitor(Map<String, Object> data, Boolean incrementViews, Boolean doCallout) {
        String visitorKey = str(data, 'visitorKey');
        if (String.isBlank(visitorKey)) {
            throw new ApiException('visitorKey is required');
        }
        String pageUrl = clip(str(data, 'pageUrl'), 1024);
        String referrer = clip(str(data, 'referrer'), 1024);
        String userAgent = clip(
            firstNonBlank(new List<String>{ str(data, 'userAgent'), header('User-Agent') }),
            1024
        );
        String language = clip(str(data, 'language'), 20);
        String timezone = clip(str(data, 'timezone'), 80);
        String ip = clip(clientIp(), 45);

        EngageIQ_Website__c site = resolveWebsite(data);
        List<EngageIQ_Visitor__c> existing = [
            SELECT Id, Visitor_Key__c, Page_View_Count__c, Status__c, Lead__c, Full_Name__c, Email__c, Phone__c,
                   Company__c, IP_Address__c, Country__c, Region__c, City__c, Timezone__c, ISP__c, First_Seen__c,
                   Website__c
            FROM EngageIQ_Visitor__c
            WHERE Visitor_Key__c = :visitorKey
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Boolean isNew = existing.isEmpty();
        Boolean ipChanged = !isNew && ip != null && ip != existing[0].IP_Address__c;
        Map<String, String> geo;
        if (doCallout && (isNew || ipChanged)) {
            geo = lookupGeo(ip);
        }

        EngageIQ_Visitor__c visitor;
        if (isNew) {
            visitor = new EngageIQ_Visitor__c(
                Visitor_Key__c = visitorKey,
                Last_Page_Url__c = pageUrl,
                Last_Referrer__c = referrer,
                Last_Seen__c = System.now(),
                First_Seen__c = System.now(),
                Page_View_Count__c = incrementViews == true ? 1 : 0,
                Status__c = 'Browsing',
                IP_Address__c = ip,
                User_Agent__c = userAgent,
                Language__c = language,
                Device_Type__c = deviceOf(userAgent),
                Timezone__c = timezone,
                Website__c = site == null ? null : site.Id,
                OwnerId = ownerId()
            );
            applyGeo(visitor, geo);
            insertSys(visitor);
            audit(
                'Visitor Arrived',
                visitor.Id,
                null,
                null,
                'Visitor',
                'Website visitor',
                ip,
                locationOf(visitor),
                pageUrl,
                'First seen from ' + (ip == null ? 'unknown IP' : ip)
            );
        } else {
            visitor = existing[0];
            if (String.isNotBlank(pageUrl)) {
                visitor.Last_Page_Url__c = pageUrl;
            }
            if (referrer != null) {
                visitor.Last_Referrer__c = referrer;
            }
            visitor.Last_Seen__c = System.now();
            if (visitor.First_Seen__c == null) {
                visitor.First_Seen__c = System.now();
            }
            if (incrementViews == true) {
                visitor.Page_View_Count__c = (visitor.Page_View_Count__c == null ? 0 : visitor.Page_View_Count__c) + 1;
            }
            if (String.isNotBlank(ip)) {
                visitor.IP_Address__c = ip;
            }
            if (String.isNotBlank(userAgent)) {
                visitor.User_Agent__c = userAgent;
                visitor.Device_Type__c = deviceOf(userAgent);
            }
            if (String.isNotBlank(language)) {
                visitor.Language__c = language;
            }
            if (String.isNotBlank(timezone)) {
                visitor.Timezone__c = timezone;
            }
            if (site != null) {
                visitor.Website__c = site.Id;
            }
            applyGeo(visitor, geo);
            updateSys(visitor);
            if (ipChanged) {
                audit(
                    'IP Changed',
                    visitor.Id,
                    null,
                    null,
                    'Visitor',
                    visitor.Full_Name__c,
                    ip,
                    locationOf(visitor),
                    pageUrl,
                    'IP changed to ' + ip
                );
            }
        }
        return visitor;
    }

    public static Map<String, Object> track(String body) {
        Map<String, Object> data = asMap(body);
        Boolean heartbeat = str(data, 'heartbeat') == 'true';
        EngageIQ_Visitor__c visitor = upsertVisitor(data, !heartbeat, true);
        String pageUrl = clip(str(data, 'pageUrl'), 1024);
        if (!heartbeat) {
            insertSys(new EngageIQ_Page_View__c(
                Visitor__c = visitor.Id,
                Website__c = visitor.Website__c,
                Page_Url__c = pageUrl,
                Referrer__c = clip(str(data, 'referrer'), 1024),
                Viewed_At__c = System.now(),
                IP_Address__c = visitor.IP_Address__c,
                Country__c = visitor.Country__c,
                City__c = visitor.City__c,
                User_Agent__c = visitor.User_Agent__c
            ));
            audit(
                'Page View',
                visitor.Id,
                null,
                null,
                'Visitor',
                visitor.Full_Name__c,
                visitor.IP_Address__c,
                locationOf(visitor),
                pageUrl,
                pageUrl
            );
        }
        return new Map<String, Object>{
            'visitorId' => visitor.Id,
            'visitorKey' => visitor.Visitor_Key__c,
            'ipAddress' => visitor.IP_Address__c,
            'location' => locationOf(visitor)
        };
    }

    public static Map<String, Object> startChat(String body) {
        Map<String, Object> data = asMap(body);
        String pageUrl = clip(str(data, 'pageUrl'), 1024);
        EngageIQ_Visitor__c visitor = upsertVisitor(data, false, true);
        List<EngageIQ_Conversation__c> openRows = [
            SELECT Id, Status__c
            FROM EngageIQ_Conversation__c
            WHERE Visitor__c = :visitor.Id AND Status__c IN ('Waiting', 'Active')
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        EngageIQ_Conversation__c convo;
        if (openRows.isEmpty()) {
            convo = new EngageIQ_Conversation__c(
                Visitor__c = visitor.Id,
                Website__c = visitor.Website__c,
                Status__c = 'Waiting',
                Page_Url__c = pageUrl,
                Started_At__c = System.now(),
                Last_Message_At__c = System.now(),
                Last_Message__c = 'Visitor started a chat',
                Visitor_Name__c = visitor.Full_Name__c,
                Unread_For_Agent__c = true,
                OwnerId = ownerId()
            );
            insertSys(convo);
            insertSys(new EngageIQ_Message__c(
                Conversation__c = convo.Id,
                Sender_Type__c = 'System',
                Body__c = 'Visitor started a chat.',
                Sent_At__c = System.now()
            ));
            if (visitor.Status__c != 'Converted') {
                visitor.Status__c = 'Chatting';
                updateSys(visitor);
            }
            audit(
                'Chat Started',
                visitor.Id,
                convo.Id,
                visitor.Lead__c,
                'Visitor',
                visitor.Full_Name__c,
                visitor.IP_Address__c,
                locationOf(visitor),
                pageUrl,
                'Query started from website'
            );
        } else {
            convo = openRows[0];
        }
        return new Map<String, Object>{ 'transcriptId' => convo.Id };
    }

    public static Map<String, Object> postMessage(String body, String senderType, Id agentId) {
        Map<String, Object> data = asMap(body);
        String transcriptRaw = str(data, 'transcriptId');
        String text = clip(str(data, 'body'), 32768);
        if (String.isBlank(transcriptRaw) || String.isBlank(text)) {
            throw new ApiException('transcriptId and body are required');
        }
        Id transcriptId = (Id) transcriptRaw;
        EngageIQ_Conversation__c convo = [
            SELECT Id, Status__c, Visitor__c, Visitor_Name__c, Agent__c
            FROM EngageIQ_Conversation__c
            WHERE Id = :transcriptId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        EngageIQ_Message__c msg = new EngageIQ_Message__c(
            Conversation__c = convo.Id,
            Sender_Type__c = senderType,
            Body__c = text,
            Sent_At__c = System.now(),
            Agent__c = agentId
        );
        insertSys(msg);
        convo.Last_Message__c = clip(text, 255);
        convo.Last_Message_At__c = System.now();
        if (senderType == 'Visitor') {
            convo.Unread_For_Agent__c = true;
            if (convo.Status__c == 'Closed') {
                convo.Status__c = 'Waiting';
                convo.Closed_At__c = null;
            }
        } else if (senderType == 'Agent') {
            convo.Unread_For_Agent__c = false;
            if (convo.Status__c == 'Waiting') {
                convo.Status__c = 'Active';
            }
            if (convo.Agent__c == null && agentId != null) {
                convo.Agent__c = agentId;
            }
        }
        updateSys(convo);
        EngageIQ_Visitor__c visitor = convo.Visitor__c == null
            ? null
            : [
                  SELECT Id, Full_Name__c, IP_Address__c, City__c, Region__c, Country__c
                  FROM EngageIQ_Visitor__c
                  WHERE Id = :convo.Visitor__c
                  WITH SYSTEM_MODE
                  LIMIT 1
              ];
        audit(
            senderType == 'Agent' ? 'Agent Message' : 'Visitor Message',
            visitor == null ? null : visitor.Id,
            convo.Id,
            null,
            senderType,
            senderType == 'Agent' ? UserInfo.getName() : (visitor == null ? 'Visitor' : visitor.Full_Name__c),
            visitor == null ? clientIp() : visitor.IP_Address__c,
            visitor == null ? null : locationOf(visitor),
            null,
            clip(text, 1000)
        );
        return new Map<String, Object>{
            'messageId' => msg.Id,
            'senderType' => senderType,
            'body' => text
        };
    }

    public static List<Map<String, Object>> listMessages(Id transcriptId, String afterId) {
        if (transcriptId == null) {
            throw new ApiException('transcriptId is required');
        }
        Datetime afterWhen;
        Id afterMessageId;
        if (String.isNotBlank(afterId)) {
            List<EngageIQ_Message__c> afterRows = [
                SELECT Id, Sent_At__c, CreatedDate
                FROM EngageIQ_Message__c
                WHERE Id = :afterId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!afterRows.isEmpty()) {
                afterWhen = afterRows[0].Sent_At__c == null ? afterRows[0].CreatedDate : afterRows[0].Sent_At__c;
                afterMessageId = afterRows[0].Id;
            }
        }
        List<EngageIQ_Message__c> rows;
        if (afterWhen == null) {
            rows = [
                SELECT Id, Sender_Type__c, Body__c, Sent_At__c
                FROM EngageIQ_Message__c
                WHERE Conversation__c = :transcriptId
                WITH SYSTEM_MODE
                ORDER BY Sent_At__c, CreatedDate, Id
                LIMIT 200
            ];
        } else {
            rows = [
                SELECT Id, Sender_Type__c, Body__c, Sent_At__c
                FROM EngageIQ_Message__c
                WHERE Conversation__c = :transcriptId
                AND (
                    Sent_At__c > :afterWhen
                    OR (Sent_At__c = :afterWhen AND Id > :afterMessageId)
                )
                WITH SYSTEM_MODE
                ORDER BY Sent_At__c, CreatedDate, Id
                LIMIT 200
            ];
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (EngageIQ_Message__c row : rows) {
            out.add(new Map<String, Object>{
                'messageId' => row.Id,
                'senderType' => row.Sender_Type__c,
                'body' => row.Body__c,
                'sentAt' => row.Sent_At__c
            });
        }
        return out;
    }

    public static Map<String, Object> captureLead(String body) {
        Map<String, Object> data = asMap(body);
        String transcriptRaw = str(data, 'transcriptId');
        String visitorRaw = str(data, 'visitorId');
        EngageIQ_Conversation__c convo;
        EngageIQ_Visitor__c visitor;
        if (String.isNotBlank(transcriptRaw)) {
            Id transcriptId = (Id) transcriptRaw;
            convo = [
                SELECT Id, Visitor__c, Lead__c
                FROM EngageIQ_Conversation__c
                WHERE Id = :transcriptId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            visitor = [
                SELECT Id, Full_Name__c, Email__c, Phone__c, Company__c, Status__c, Lead__c, IP_Address__c,
                       City__c, Region__c, Country__c
                FROM EngageIQ_Visitor__c
                WHERE Id = :convo.Visitor__c
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } else if (String.isNotBlank(visitorRaw)) {
            visitor = [
                SELECT Id, Full_Name__c, Email__c, Phone__c, Company__c, Status__c, Lead__c, IP_Address__c,
                       City__c, Region__c, Country__c
                FROM EngageIQ_Visitor__c
                WHERE Id = :visitorRaw
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } else {
            throw new ApiException('transcriptId or visitorId is required');
        }

        String name = firstNonBlank(new List<String>{ str(data, 'name'), str(data, 'fullName'), visitor.Full_Name__c });
        String firstName = str(data, 'firstName');
        String lastName = str(data, 'lastName');
        if (String.isBlank(lastName) && String.isNotBlank(name)) {
            List<String> parts = name.normalizeSpace().split(' ', 2);
            if (parts.size() == 1) {
                lastName = parts[0];
            } else {
                firstName = parts[0];
                lastName = parts[1];
            }
        }
        if (String.isBlank(lastName)) {
            lastName = 'Website visitor';
        }
        String email = firstNonBlank(new List<String>{ str(data, 'email'), visitor.Email__c });
        String phone = firstNonBlank(new List<String>{ str(data, 'phone'), visitor.Phone__c });
        String company = firstNonBlank(new List<String>{ str(data, 'company'), visitor.Company__c, 'EngageIQ Chat' });
        String fullName = String.isBlank(name)
            ? ((firstName == null ? '' : firstName + ' ') + lastName).trim()
            : name;

        visitor.Full_Name__c = clip(fullName, 80);
        visitor.Email__c = email;
        visitor.Phone__c = phone;
        visitor.Company__c = clip(company, 80);
        visitor.Status__c = 'Converted';
        updateSys(visitor);
        if (convo != null) {
            convo.Visitor_Name__c = visitor.Full_Name__c;
            updateSys(convo);
            insertSys(new EngageIQ_Message__c(
                Conversation__c = convo.Id,
                Sender_Type__c = 'System',
                Body__c = 'Contact details saved. Salesforce Lead is being created.',
                Sent_At__c = System.now()
            ));
        }
        EventBus.publish(
            new EngageIQ_Lead_Request__e(
                Visitor_Id__c = String.valueOf(visitor.Id),
                Conversation_Id__c = convo == null ? null : String.valueOf(convo.Id),
                Full_Name__c = fullName,
                Email__c = email,
                Phone__c = phone,
                Company__c = company
            )
        );
        audit(
            'Lead Created',
            visitor.Id,
            convo == null ? null : convo.Id,
            visitor.Lead__c,
            UserInfo.getUserType() == 'Guest' ? 'Visitor' : 'Agent',
            UserInfo.getUserType() == 'Guest' ? visitor.Full_Name__c : UserInfo.getName(),
            visitor.IP_Address__c,
            locationOf(visitor),
            null,
            'Lead requested for Salesforce conversion'
        );
        return new Map<String, Object>{
            'leadId' => visitor.Lead__c,
            'transcriptId' => convo == null ? null : convo.Id,
            'visitorId' => visitor.Id
        };
    }

    static Map<String, Object> toMap(SObject rec) {
        return rec == null ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(rec));
    }

    static List<Map<String, Object>> toMapList(List<SObject> rows) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (rows == null) {
            return out;
        }
        for (SObject row : rows) {
            out.add(toMap(row));
        }
        return out;
    }

    static String visitorSelect() {
        return 'Id, Name, Visitor_Key__c, Status__c, Last_Page_Url__c, Last_Referrer__c, Last_Seen__c, First_Seen__c, ' +
            'Page_View_Count__c, Full_Name__c, Email__c, Phone__c, Company__c, Lead__c, IP_Address__c, Country__c, ' +
            'Region__c, City__c, Location_Label__c, Timezone__c, ISP__c, Device_Type__c, Language__c, Is_Online__c, ' +
            'Latitude__c, Longitude__c, Website__c, Website__r.Name, Website__r.Domain__c, Website__r.Site_Key__c';
    }

    public static Map<String, Object> loadHome() {
        return loadHome(null);
    }

    public static Map<String, Object> loadHome(Id websiteId) {
        Datetime liveSince = System.now().addMinutes(-2);
        String convoFilter = websiteId == null ? '' : ' AND Website__c = :websiteId';
        String visitorFilter = websiteId == null ? '' : ' AND Website__c = :websiteId';
        List<AggregateResult> waiting = Database.query(
            'SELECT COUNT(Id) cnt FROM EngageIQ_Conversation__c WHERE Status__c = \'Waiting\'' +
                convoFilter +
                ' WITH SYSTEM_MODE'
        );
        List<AggregateResult> active = Database.query(
            'SELECT COUNT(Id) cnt FROM EngageIQ_Conversation__c WHERE Status__c = \'Active\'' +
                convoFilter +
                ' WITH SYSTEM_MODE'
        );
        List<AggregateResult> visitors = Database.query(
            'SELECT COUNT(Id) cnt FROM EngageIQ_Visitor__c WHERE Id != null' + visitorFilter + ' WITH SYSTEM_MODE'
        );
        List<AggregateResult> converted = Database.query(
            'SELECT COUNT(Id) cnt FROM EngageIQ_Visitor__c WHERE Status__c = \'Converted\'' +
                visitorFilter +
                ' WITH SYSTEM_MODE'
        );
        List<AggregateResult> live = Database.query(
            'SELECT COUNT(Id) cnt FROM EngageIQ_Visitor__c WHERE Last_Seen__c >= :liveSince' +
                visitorFilter +
                ' WITH SYSTEM_MODE'
        );
        List<EngageIQ_Visitor__c> liveRows = Database.query(
            'SELECT ' +
                visitorSelect() +
                ' FROM EngageIQ_Visitor__c WHERE Last_Seen__c >= :liveSince' +
                visitorFilter +
                ' WITH SYSTEM_MODE ORDER BY Last_Seen__c DESC LIMIT 50'
        );
        List<EngageIQ_Visitor__c> recent = Database.query(
            'SELECT ' +
                visitorSelect() +
                ' FROM EngageIQ_Visitor__c WHERE Id != null' +
                visitorFilter +
                ' WITH SYSTEM_MODE ORDER BY Last_Seen__c DESC NULLS LAST, CreatedDate DESC LIMIT 30'
        );
        List<EngageIQ_Conversation__c> queue = Database.query(
            'SELECT Id, Name, Status__c, Visitor_Name__c, Last_Message__c, Last_Message_At__c, Unread_For_Agent__c, ' +
                'Page_Url__c, Website__c, Website__r.Name, Website__r.Domain__c FROM EngageIQ_Conversation__c ' +
                'WHERE Status__c IN (\'Waiting\', \'Active\')' +
                convoFilter +
                ' WITH SYSTEM_MODE ORDER BY Last_Message_At__c DESC NULLS LAST, CreatedDate DESC LIMIT 50'
        );
        String auditFilter = websiteId == null ? '' : ' WHERE Visitor__r.Website__c = :websiteId';
        List<EngageIQ_Audit__c> auditRows = Database.query(
            'SELECT Id, Name, Event_Type__c, Actor_Type__c, Actor_Name__c, IP_Address__c, Location__c, Page_Url__c, ' +
                'Details__c, Occurred_At__c, Visitor__c, Conversation__c, Lead__c FROM EngageIQ_Audit__c' +
                auditFilter +
                ' WITH SYSTEM_MODE ORDER BY Occurred_At__c DESC, CreatedDate DESC LIMIT 40'
        );
        Map<String, Object> payload = new Map<String, Object>{
            'waitingCount' => (Integer) waiting[0].get('cnt'),
            'activeCount' => (Integer) active[0].get('cnt'),
            'visitorCount' => (Integer) visitors[0].get('cnt'),
            'convertedCount' => (Integer) converted[0].get('cnt'),
            'liveCount' => (Integer) live[0].get('cnt'),
            'liveVisitors' => toMapList(liveRows),
            'queue' => toMapList(queue),
            'visitors' => toMapList(recent),
            'audit' => toMapList(auditRows),
            'websiteId' => websiteId,
            'widgetBaseUrl' => widgetBaseUrl()
        };
        payload.putAll(listWebsites());
        return payload;
    }

    public static Map<String, Object> loadInbox(Id conversationId) {
        List<EngageIQ_Conversation__c> rows = [
            SELECT Id, Name, Status__c, Visitor__c, Visitor_Name__c, Last_Message__c, Last_Message_At__c,
                   Unread_For_Agent__c, Page_Url__c, Agent__c, Lead__c, Started_At__c, Website__c,
                   Website__r.Name, Website__r.Domain__c
            FROM EngageIQ_Conversation__c
            WHERE Status__c IN ('Waiting', 'Active', 'Closed')
            WITH SYSTEM_MODE
            ORDER BY Last_Message_At__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 80
        ];
        EngageIQ_Conversation__c selected;
        if (conversationId != null) {
            for (EngageIQ_Conversation__c row : rows) {
                if (row.Id == conversationId) {
                    selected = row;
                    break;
                }
            }
            if (selected == null) {
                List<EngageIQ_Conversation__c> found = [
                    SELECT Id, Name, Status__c, Visitor__c, Visitor_Name__c, Last_Message__c, Last_Message_At__c,
                           Unread_For_Agent__c, Page_Url__c, Agent__c, Lead__c, Started_At__c, Website__c,
                           Website__r.Name, Website__r.Domain__c
                    FROM EngageIQ_Conversation__c
                    WHERE Id = :conversationId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                if (!found.isEmpty()) {
                    selected = found[0];
                }
            }
        } else if (!rows.isEmpty()) {
            selected = rows[0];
        }
        Map<String, Object> payload = new Map<String, Object>{
            'conversations' => toMapList(rows),
            'conversationId' => selected == null ? null : selected.Id
        };
        payload.putAll(themePayload());
        if (selected != null) {
            payload.put('conversation', toMap(selected));
            if (selected.Visitor__c != null) {
                Id visitorId = selected.Visitor__c;
                List<EngageIQ_Visitor__c> visitorRows = Database.query(
                    'SELECT ' + visitorSelect() + ' FROM EngageIQ_Visitor__c WHERE Id = :visitorId WITH SYSTEM_MODE LIMIT 1'
                );
                if (!visitorRows.isEmpty()) {
                    payload.put('visitor', toMap(visitorRows[0]));
                }
                payload.put('audit', toMapList([
                    SELECT Id, Name, Event_Type__c, Actor_Type__c, Actor_Name__c, IP_Address__c, Location__c, Page_Url__c,
                           Details__c, Occurred_At__c, Lead__c
                    FROM EngageIQ_Audit__c
                    WHERE Visitor__c = :visitorId
                    WITH SYSTEM_MODE
                    ORDER BY Occurred_At__c DESC, CreatedDate DESC
                    LIMIT 40
                ]));
            }
            payload.put('messages', listMessages(selected.Id, null));
        }
        return payload;
    }

    public static Map<String, Object> assignToMe(Id conversationId) {
        EngageIQ_Conversation__c convo = [
            SELECT Id, Status__c, Agent__c, Visitor__c
            FROM EngageIQ_Conversation__c
            WHERE Id = :conversationId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        convo.Agent__c = UserInfo.getUserId();
        if (convo.Status__c == 'Waiting') {
            convo.Status__c = 'Active';
        }
        convo.Unread_For_Agent__c = false;
        updateSys(convo);
        audit(
            'Agent Assigned',
            convo.Visitor__c,
            convo.Id,
            null,
            'Agent',
            UserInfo.getName(),
            null,
            null,
            null,
            'Assigned to ' + UserInfo.getName()
        );
        return loadInbox(conversationId);
    }

    public static Map<String, Object> closeConversation(Id conversationId) {
        EngageIQ_Conversation__c convo = [
            SELECT Id, Visitor__c, Status__c
            FROM EngageIQ_Conversation__c
            WHERE Id = :conversationId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        convo.Status__c = 'Closed';
        convo.Closed_At__c = System.now();
        convo.Unread_For_Agent__c = false;
        updateSys(convo);
        insertSys(new EngageIQ_Message__c(
            Conversation__c = convo.Id,
            Sender_Type__c = 'System',
            Body__c = 'Conversation closed by agent.',
            Sent_At__c = System.now(),
            Agent__c = UserInfo.getUserId()
        ));
        audit(
            'Conversation Closed',
            convo.Visitor__c,
            convo.Id,
            null,
            'Agent',
            UserInfo.getName(),
            null,
            null,
            null,
            'Closed by agent'
        );
        return loadInbox(conversationId);
    }
}