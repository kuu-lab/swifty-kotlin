import java.security.MessageDigest
import java.security.NoSuchAlgorithmException

// KUU-4315: bundled java.security.MessageDigest must accept exactly the
// spellings the JDK's SUN provider registers for each digest — the service
// name, its KnownOIDs aliases, and the "OID.<oid>" / bare "<oid>" forms,
// matched case-insensitively — and reject dash-folding lookalikes such as
// "SHA3256", "SHA-3-256", "S-H-A-256" and "MD-5" with
// NoSuchAlgorithmException like the JDK.

fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

fun main() {
    // Spellings the JDK accepts for each bundled algorithm.
    val accepted = listOf(
        // MD2 (OID 1.2.840.113549.2.2) and MD5 (OID 1.2.840.113549.2.5)
        "MD2", "md2", "OID.1.2.840.113549.2.2", "1.2.840.113549.2.2",
        "MD5", "md5", "OID.1.2.840.113549.2.5", "1.2.840.113549.2.5",
        // SHA-1 service: aliases "SHA", "SHA-1", "SHA1" + OID 1.3.14.3.2.26
        "SHA", "SHA-1", "SHA1", "sha", "sHa-1", "OID.1.3.14.3.2.26", "1.3.14.3.2.26",
        // SHA-224/256/384/512 (NIST OIDs 2.16.840.1.101.3.4.2.4/.1/.2/.3)
        "SHA-224", "SHA224", "sha224", "OID.2.16.840.1.101.3.4.2.4", "2.16.840.1.101.3.4.2.4",
        "SHA-256", "SHA256", "sha256", "OID.2.16.840.1.101.3.4.2.1", "2.16.840.1.101.3.4.2.1",
        "SHA-384", "SHA384", "OID.2.16.840.1.101.3.4.2.2", "2.16.840.1.101.3.4.2.2",
        "SHA-512", "SHA512", "OID.2.16.840.1.101.3.4.2.3", "2.16.840.1.101.3.4.2.3",
        // SHA-512/224 and SHA-512/256 truncation variants (OIDs .2.5/.2.6)
        "SHA-512/224", "SHA512/224", "sha-512/224", "OID.2.16.840.1.101.3.4.2.5", "2.16.840.1.101.3.4.2.5",
        "SHA-512/256", "SHA512/256", "OID.2.16.840.1.101.3.4.2.6", "2.16.840.1.101.3.4.2.6",
        // SHA3 family (OIDs .2.7-.2.10): only the "SHA3-<bits>" spelling is registered
        "SHA3-224", "sha3-224", "OID.2.16.840.1.101.3.4.2.7", "2.16.840.1.101.3.4.2.7",
        "SHA3-256", "sha3-256", "OID.2.16.840.1.101.3.4.2.8", "2.16.840.1.101.3.4.2.8",
        "SHA3-384", "OID.2.16.840.1.101.3.4.2.9", "2.16.840.1.101.3.4.2.9",
        "SHA3-512", "OID.2.16.840.1.101.3.4.2.10", "2.16.840.1.101.3.4.2.10",
        // SHAKE: "SHAKE128"/"SHAKE256" are aliases of the -256/-512 services
        // (OIDs .2.11/.2.12)
        "SHAKE128", "SHAKE128-256", "shake128-256", "OID.2.16.840.1.101.3.4.2.11", "2.16.840.1.101.3.4.2.11",
        "SHAKE256", "SHAKE256-512", "OID.2.16.840.1.101.3.4.2.12", "2.16.840.1.101.3.4.2.12"
    )
    for (name in accepted) {
        val md = MessageDigest.getInstance(name)
        println("ok|" + name + "|" + md.algorithm + "|" + md.digestLength + "|" +
            hex(md.digest("abc".encodeToByteArray())))
    }

    // Spellings the JDK rejects even though dash-folding would map them
    // onto a supported algorithm (or that are simply unregistered).
    val rejected = listOf(
        "SHA3256", "SHA-3-256", "SHA-3-224", "S-H-A-256", "S-H-A", "SHA--256",
        "SHA25-6", "SHA-25-6", "MD-5", "M-D-5", "MD-2", "MD 5",
        "SHA-512-224", "SHA-512-256", "SHA512224", "SHA512256", "SHA-512224",
        "SHA512/384", "SHA-512/384", "SHA512384",
        "SHA3224", "SHA3384", "SHA3512", "SHA3_256", "SHA3 256", "SHA3",
        "SHAKE-128", "SHAKE-256", "SHAKE128256", "SHAKE256512", "SHAKE128-512",
        "SHAKE128-LEN", "SHA256withRSA", "SHA1withRSA", "HmacSHA256",
        "Tiger", "Tiger/192", "RIPEMD160", "WHIRLPOOL",
        "OID.MD5", "OID.SHA-256", "OID.SHA256",
        "SHA-256 ", " SHA-256", "SHA256/", "", " "
    )
    for (name in rejected) {
        try {
            MessageDigest.getInstance(name)
            println("BAD|" + name + "|NO-THROW")
        } catch (e: NoSuchAlgorithmException) {
            println("rej|" + name + "|" + e.message)
        }
    }
}
