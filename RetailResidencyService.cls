public with sharing class RetailResidencyService {
    public static final String RESIDENT = 'Resident';
    public static final String NON_RESIDENT = 'Non Resident';

    public class Classification {
        @AuraEnabled public String countryCode;
        @AuraEnabled public String countryName;
        @AuraEnabled public String residentStatus;
        @AuraEnabled public Boolean homeCountry;
        @AuraEnabled public String reason;
        @AuraEnabled public String nationality;
    }

    public static String homeCountryCode() {
        List<Retail_Config__mdt> rows = [
            SELECT Home_Country_Code__c, Home_Country_Name__c
            FROM Retail_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!rows.isEmpty() && String.isNotBlank(rows[0].Home_Country_Code__c)) {
            return rows[0].Home_Country_Code__c.trim().toUpperCase();
        }
        return 'IN';
    }

    public static String homeCountryName() {
        List<Retail_Config__mdt> rows = [
            SELECT Home_Country_Name__c
            FROM Retail_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!rows.isEmpty() && String.isNotBlank(rows[0].Home_Country_Name__c)) {
            return rows[0].Home_Country_Name__c.trim();
        }
        return 'India';
    }

    public static Boolean isHomeCountry(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        String normalized = value.trim().toUpperCase().replace('.', ' ').replace('-', ' ');
        while (normalized.contains('  ')) {
            normalized = normalized.replace('  ', ' ');
        }
        String home = homeCountryCode();
        String homeName = homeCountryName().toUpperCase();
        Set<String> tokens = new Set<String>{
            home,
            homeName,
            'IN',
            'IND',
            'INDIA',
            'INDIAN',
            'BHARAT',
            'HINDUSTAN'
        };
        if (home == 'IN') {
            tokens.add('IND');
        }
        if (tokens.contains(normalized)) {
            return true;
        }
        if (normalized.contains('INDIA') || normalized.contains('INDIAN')) {
            return true;
        }
        if (normalized.contains('P<IND') || normalized.startsWith('P<IND')) {
            return true;
        }
        return false;
    }

    public static Classification classifyCountry(String countryOrNationality) {
        Classification out = new Classification();
        out.homeCountry = isHomeCountry(countryOrNationality);
        out.residentStatus = out.homeCountry ? RESIDENT : NON_RESIDENT;
        out.countryName = countryOrNationality;
        out.nationality = countryOrNationality;
        if (out.homeCountry) {
            out.countryCode = homeCountryCode();
            out.reason = 'Passport / nationality is ' + homeCountryName() + ', so the customer is marked Resident.';
        } else {
            out.countryCode = extractIsoHint(countryOrNationality);
            out.reason = 'Passport / nationality is not ' + homeCountryName() +
                ', so the customer is marked Non Resident (foreign national).';
        }
        return out;
    }

    public static Classification classifyPassport(String ocrText, String fileName) {
        String blobText = ((ocrText == null ? '' : ocrText) + ' ' + (fileName == null ? '' : fileName)).toUpperCase();
        Matcher mrz = Pattern.compile('P[<K]([A-Z]{3})').matcher(blobText.replace(' ', ''));
        if (mrz.find()) {
            return classifyCountry(mrz.group(1));
        }
        Matcher nation = Pattern.compile('NATIONALITY[:\\s]+([A-Z]{2,20})').matcher(blobText);
        if (nation.find()) {
            return classifyCountry(nation.group(1));
        }
        Matcher country = Pattern.compile('COUNTRY[:\\s]+([A-Z]{2,20})').matcher(blobText);
        if (country.find()) {
            return classifyCountry(country.group(1));
        }
        if (blobText.contains('INDIA') || blobText.contains('INDIAN') || blobText.contains('BHARAT')) {
            return classifyCountry('INDIA');
        }
        Map<String, String> aliases = new Map<String, String>{
            'UNITED KINGDOM' => 'GB',
            'GREAT BRITAIN' => 'GB',
            'BRITISH' => 'GB',
            'UNITED STATES' => 'US',
            'AMERICAN' => 'US',
            'UAE' => 'AE',
            'EMIRATI' => 'AE',
            'SINGAPORE' => 'SG',
            'PAKISTAN' => 'PK',
            'BANGLADESH' => 'BD',
            'NEPAL' => 'NP',
            'SRILANKA' => 'LK',
            'SRI LANKA' => 'LK'
        };
        for (String key : aliases.keySet()) {
            if (blobText.contains(key)) {
                return classifyCountry(aliases.get(key));
            }
        }
        Classification unknown = new Classification();
        unknown.residentStatus = null;
        unknown.reason = 'Passport country could not be detected. Choose nationality to set Resident or Non Resident.';
        return unknown;
    }

    public static Decimal parseAmount(String text, List<String> labels) {
        if (String.isBlank(text)) {
            return null;
        }
        String compact = text.replace('\n', ' ');
        for (String label : labels) {
            Matcher m = Pattern.compile('(?i)' + label + '[^0-9]{0,20}([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]+)?|[0-9]+(?:\\.[0-9]+)?)').matcher(compact);
            if (m.find()) {
                return Decimal.valueOf(m.group(1).replace(',', ''));
            }
        }
        return null;
    }

    public static String parseEmployer(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Matcher m = Pattern.compile('(?i)(?:employer|company|organisation|organization)[:\\s]+([A-Za-z0-9 &.]{3,80})').matcher(text);
        if (m.find()) {
            return m.group(1).trim();
        }
        return null;
    }

    static String extractIsoHint(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String v = value.trim().toUpperCase();
        if (v.length() == 2 || v.length() == 3) {
            return v;
        }
        return v.left(80);
    }
}