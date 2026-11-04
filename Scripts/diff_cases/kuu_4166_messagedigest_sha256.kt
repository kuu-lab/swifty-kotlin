import java.security.MessageDigest
import java.security.NoSuchAlgorithmException

// KUU-4166: bundled java.security.MessageDigest implements SHA-256 in
// addition to MD5. Pins JVM parity for the canonical digest vectors,
// incremental update() buffering, digest(data) append semantics,
// digest(output, offset, length), per-algorithm digestLength, algorithm
// name echo, case/hyphen-insensitive lookup, and the
// NoSuchAlgorithmException message for unsupported names.

fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

fun main() {
    val md = MessageDigest.getInstance("SHA-256")
    println(md.algorithm)
    println(md.digestLength)
    println(hex(md.digest("abc".encodeToByteArray())))

    println(hex(MessageDigest.getInstance("SHA-256").digest()))

    val incremental = MessageDigest.getInstance("SHA-256")
    incremental.update("a".encodeToByteArray())
    incremental.update("bc".encodeToByteArray())
    println(hex(incremental.digest()))
    println(hex(incremental.digest()))
    incremental.update('a'.code.toByte())
    incremental.update('b'.code.toByte())
    incremental.update('c'.code.toByte())
    println(hex(incremental.digest()))

    // JVM digest(data) appends to the buffered input instead of resetting.
    incremental.update("zzz".encodeToByteArray())
    println(hex(incremental.digest("abc".encodeToByteArray())))

    // More than one 64-byte block exercises the multi-block loop.
    val multiBlock = ByteArray(200) { (it % 256).toByte() }
    println(hex(MessageDigest.getInstance("SHA-256").digest(multiBlock)))

    val output = ByteArray(40)
    val written = MessageDigest.getInstance("SHA-256").digest(output, 4, 32)
    println(written)
    println(hex(output))

    // Lookup is case- and hyphen-insensitive; the requested name is echoed.
    println(MessageDigest.getInstance("SHA256").algorithm)
    println(MessageDigest.getInstance("sha-256").algorithm)
    println(MessageDigest.getInstance("sHa256").digestLength)
    println(hex(MessageDigest.getInstance("SHA256").digest("abc".encodeToByteArray())))

    val sliced = MessageDigest.getInstance("SHA-256")
    val wrapped = "xxabcxx".encodeToByteArray()
    sliced.update(wrapped, 2, 3)
    println(hex(sliced.digest()))

    println(
        MessageDigest.isEqual(
            MessageDigest.getInstance("SHA-256").digest("abc".encodeToByteArray()),
            MessageDigest.getInstance("SHA-256").digest("abc".encodeToByteArray())
        )
    )

    // MD5 keeps working and now echoes the requested name.
    val md5 = MessageDigest.getInstance("md5")
    println(md5.algorithm)
    println(md5.digestLength)
    println(hex(md5.digest("test".encodeToByteArray())))
    md5.update("zzz".encodeToByteArray())
    println(hex(md5.digest("abc".encodeToByteArray())))

    try {
        MessageDigest.getInstance("FOO")
    } catch (e: NoSuchAlgorithmException) {
        println(e.message)
    }
    try {
        MessageDigest.getInstance("SHA_256")
    } catch (e: NoSuchAlgorithmException) {
        println(e.message)
    }
}
