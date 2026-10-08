import Foundation

/// A throwaway P-256 key in the same PKCS#8 PEM shape Apple hands out as a
/// `.p8`. Generated for these tests only. It authenticates nothing.
public enum TestKeys {
    public static let privateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg+93IOlpopuMCvKOT
    j6JmNQEck99p7mHrx3jo+EDDe+yhRANCAARftryy4A6MuhdolnijBx83+mQiDheD
    drEgWMok4f86ZodnPWLtc8KoBNNzxarAKlGH2CCIWLgBIawSpuaYovQt
    -----END PRIVATE KEY-----
    """

    public static let keyID = "2X9R4HXF34"
    public static let issuerID = "57246542-96fe-1a63-e053-0824d011072a"
}
