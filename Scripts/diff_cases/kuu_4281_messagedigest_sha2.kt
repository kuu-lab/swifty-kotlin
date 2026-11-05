import java.security.MessageDigest
import java.security.NoSuchAlgorithmException

// KUU-4281: bundled java.security.MessageDigest implements the rest of the
// SHA-2 family (SHA-224, SHA-384, SHA-512, SHA-512/224, SHA-512/256), MD2,
// and the SHA-3 family (SHA3-224/256/384/512) in addition to MD5, SHA-1 and
// SHA-256. Pins JVM parity for canonical digest vectors, incremental
// update() buffering, digest(data) append semantics, digest(output, offset,
// length), per-algorithm digestLength, case/hyphen-insensitive lookup, and
// the NoSuchAlgorithmException message for unsupported names.
// SHAKE128/SHAKE256 (XOF) remain unsupported — deferred to a follow-up.

fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

fun main() {
    val algs = listOf(
        "MD2", "SHA-224", "SHA-384", "SHA-512", "SHA-512/224", "SHA-512/256",
        "SHA3-224", "SHA3-256", "SHA3-384", "SHA3-512"
    )
    val inputs = listOf(
        "",
        "abc",
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        "The quick brown fox jumps over the lazy dog"
    )
    for (a in algs) {
        for (inp in inputs) {
            val md = MessageDigest.getInstance(a)
            println(a + "|" + inp.length + "|" + md.digestLength + "|" + hex(md.digest(inp.encodeToByteArray())))
        }
    }

    // Inputs straddling the 128-byte SHA-512 block padding boundary and the
    // SHA3-256 rate boundary (136 bytes), plus the 200-byte multi-block case.
    for (size in listOf(111, 112, 113, 127, 128, 129)) {
        val boundary = ByteArray(size) { (it * 7 + 3).toByte() }
        println("SHA-512|" + size + "|" + hex(MessageDigest.getInstance("SHA-512").digest(boundary)))
        println("SHA3-256|" + size + "|" + hex(MessageDigest.getInstance("SHA3-256").digest(boundary)))
    }
    val multiBlock = ByteArray(200) { (it % 256).toByte() }
    for (a in algs) {
        println(a + "|200|" + hex(MessageDigest.getInstance(a).digest(multiBlock)))
    }

    // Incremental update() buffering.
    val inc = MessageDigest.getInstance("SHA512")
    inc.update("ab".encodeToByteArray())
    inc.update("c".encodeToByteArray())
    println("SHA512-incr|" + hex(inc.digest()))
    println("SHA512-incr2|" + hex(inc.digest()))

    // digest(data) appends to buffered input rather than resetting.
    inc.update("zzz".encodeToByteArray())
    println("SHA512-append|" + hex(inc.digest("abc".encodeToByteArray())))

    // digest(output, offset, length) writes digestLength bytes at offset.
    val out = ByteArray(80)
    val written = MessageDigest.getInstance("SHA-512").digest(out, 8, 64)
    println("SHA-512-out|" + written + "|" + hex(out))
    val out32 = ByteArray(40)
    val written32 = MessageDigest.getInstance("SHA3-256").digest(out32, 4, 32)
    println("SHA3-256-out|" + written32 + "|" + hex(out32))

    // Lookup is case- and hyphen-insensitive; the requested name is echoed.
    println(MessageDigest.getInstance("SHA512").algorithm)
    println(MessageDigest.getInstance("sha-512").algorithm)
    println(MessageDigest.getInstance("SHA384").digestLength)
    println(MessageDigest.getInstance("SHA-512/224").digestLength)
    println(MessageDigest.getInstance("SHA512/224").digestLength)
    println(MessageDigest.getInstance("SHA512/256").digestLength)
    println(MessageDigest.getInstance("sha512/256").algorithm)
    println(MessageDigest.getInstance("SHA3-256").algorithm)
    println(MessageDigest.getInstance("sha3-384").digestLength)
    println(MessageDigest.getInstance("MD2").algorithm)
    println(MessageDigest.getInstance("md2").digestLength)

    // Aliases accepted by both JVM and the bundled implementation.
    println(hex(MessageDigest.getInstance("SHA512/224").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("SHA512/256").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("sha3-256").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("MD2").digest("abc".encodeToByteArray())))

    // MD5, SHA-1 and SHA-256 keep working.
    println(hex(MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())))
    println(MessageDigest.getInstance("MD5").digestLength)
    println(hex(MessageDigest.getInstance("SHA-1").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("SHA-256").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("SHA-224").digest("abc".encodeToByteArray())))

    // Names rejected by both JVM and the bundled implementation.
    for (name in listOf("FOO", "SHA_512", "SHA-512-256", "SHA512256", "SHA3", "SHA-3", "MD4", "SHAKE", "RIPEMD160", "Keccak-256")) {
        try {
            MessageDigest.getInstance(name)
            println(name + "|NO-THROW")
        } catch (e: NoSuchAlgorithmException) {
            println(name + "|" + e.message)
        }
    }
}
