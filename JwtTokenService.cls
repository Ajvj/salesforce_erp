/**
 * Builds the short-lived signed JWT Apex attaches to every outbound callout
 * to the Java banking API. The Java service trusts the "sub" claim as the
 * calling customer's identifier - see java-backend README-salesforce-setup.md
 * for how the signing certificate and audience must line up on both sides.
 */
public with sharing class JwtTokenService {

    private static final Integer TOKEN_VALIDITY_SECONDS = 300;
    private static final String CERTIFICATE_NAME = 'JavaBankingApiCert';
    private static final String AUDIENCE = 'internet-banking-api';
    private static final String ISSUER = 'salesforce-internet-banking';

    public static String buildAccessToken(Id contactId) {
        Auth.JWT jwt = new Auth.JWT();
        jwt.setSub(contactId);
        jwt.setAud(AUDIENCE);
        jwt.setIss(ISSUER);
        jwt.setValidityLength(TOKEN_VALIDITY_SECONDS);

        Auth.JWS jws = new Auth.JWS(jwt, CERTIFICATE_NAME);
        return jws.getCompactSerialization();
    }
}