import java.security.DigestException
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException

// KUU-4306: bundled java.security.MessageDigest accepts SHAKE128/SHAKE256
// (plus the JDK's SHAKE128-256/SHAKE256-512 spellings). Pins JVM parity for
// the fixed digestLength contract (32/64 bytes), canonical XOF vectors,
// alias spellings, the JDK reset semantics (each digest() finalizes and the
// next digest() restarts from an empty buffer — the JDK SHAKE providers do
// not continue the XOF stream across digest() calls), digest(data) append
// semantics, update() bounds checking, and the DigestException /
// IllegalArgumentException / index-error split in digest(output, offset,
// length).

fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

fun probeDigestOut(md: MessageDigest, out: ByteArray, offset: Int, length: Int): String = try {
    "ok|" + md.digest(out, offset, length)
} catch (e: DigestException) {
    "DigestException"
} catch (e: IllegalArgumentException) {
    "IllegalArgumentException"
} catch (e: IndexOutOfBoundsException) {
    "IndexOutOfBounds"
} catch (e: Exception) {
    "Exception"
}

fun probeUpdate(data: ByteArray, offset: Int, length: Int): String = try {
    MessageDigest.getInstance("SHAKE128").update(data, offset, length)
    "ok"
} catch (e: IllegalArgumentException) {
    "IllegalArgumentException"
} catch (e: IndexOutOfBoundsException) {
    "IndexOutOfBounds"
} catch (e: Exception) {
    "Exception"
}

fun main() {
    // digestLength and canonical vectors for the empty and "abc" inputs.
    for (name in listOf("SHAKE128", "SHAKE256", "SHAKE128-256", "SHAKE256-512")) {
        val md = MessageDigest.getInstance(name)
        println(name + "|" + md.algorithm + "|" + md.digestLength + "|" +
            hex(md.digest("".encodeToByteArray())) + "|" +
            hex(md.digest("abc".encodeToByteArray())))
    }

    // Case-insensitive aliases; the requested spelling is echoed back.
    println(MessageDigest.getInstance("shake128").algorithm)
    println(MessageDigest.getInstance("Shake256").digestLength)
    println(hex(MessageDigest.getInstance("sHaKe128-256").digest("abc".encodeToByteArray())))
    println(hex(MessageDigest.getInstance("shake256-512").digest("abc".encodeToByteArray())))

    // JDK reset semantics: after digest() the buffered input is consumed, so
    // a following digest() computes over an empty message (the XOF stream
    // does not continue across digest() calls on the JDK).
    val cont = MessageDigest.getInstance("SHAKE128")
    cont.update("abc".encodeToByteArray())
    println("c1|" + hex(cont.digest()))
    println("c2|" + hex(cont.digest()))
    println("c3|" + hex(cont.digest()))

    // update() after digest() starts a fresh computation.
    val upd = MessageDigest.getInstance("SHAKE128")
    upd.update("abc".encodeToByteArray())
    println("u1|" + hex(upd.digest()))
    upd.update("def".encodeToByteArray())
    println("u2|" + hex(upd.digest()))

    // digest(data) appends to buffered input before finalizing.
    val app = MessageDigest.getInstance("SHAKE256")
    app.update("abc".encodeToByteArray())
    println("a1|" + hex(app.digest("def".encodeToByteArray())))
    println("a2|" + hex(app.digest("ghi".encodeToByteArray())))

    // reset() discards buffered input and any consumed state.
    val rst = MessageDigest.getInstance("SHAKE256")
    rst.update("abc".encodeToByteArray())
    rst.digest()
    rst.update("zzz".encodeToByteArray())
    rst.reset()
    rst.update("abc".encodeToByteArray())
    println("r|" + hex(rst.digest()))

    // Incremental updates: ranged form, single byte, and zero-length updates
    // (a no-op for in-range or negative offsets; a positive out-of-range
    // offset still fails the facade bounds check, as on the JDK).
    val inc = MessageDigest.getInstance("SHAKE128")
    inc.update("ab".encodeToByteArray())
    inc.update(byteArrayOf('c'.code.toByte()))
    val ranged = "def".encodeToByteArray()
    inc.update(ranged, 0, 3)
    inc.update(ranged, 1, 0)
    inc.update(ranged, -5, 0)
    println("i|" + hex(inc.digest()))

    // Inputs straddling the SHAKE128 rate (168 bytes) and SHAKE256 rate
    // (136 bytes) boundaries, plus a multi-block case.
    for (size in listOf(135, 136, 137, 167, 168, 169, 200)) {
        val boundary = ByteArray(size) { (it * 7 + 3).toByte() }
        println("b128|" + size + "|" + hex(MessageDigest.getInstance("SHAKE128").digest(boundary)))
        println("b256|" + size + "|" + hex(MessageDigest.getInstance("SHAKE256").digest(boundary)))
    }

    // digest(output, offset, length): writes digestLength bytes at offset and
    // returns digestLength, even when length is larger.
    val out = ByteArray(100)
    val okMd = MessageDigest.getInstance("SHAKE128")
    okMd.update("abc".encodeToByteArray())
    println("o1|" + probeDigestOut(okMd, out, 5, 40) + "|" + hex(out))
    val okMd2 = MessageDigest.getInstance("SHAKE256")
    okMd2.update("abc".encodeToByteArray())
    println("o2|" + probeDigestOut(okMd2, out, 0, 64) + "|" + hex(out))
    val okMd3 = MessageDigest.getInstance("SHAKE128")
    okMd3.update("abc".encodeToByteArray())
    println("o3|" + probeDigestOut(okMd3, out, 68, 32))

    // digest(output, offset, length) failure split: the facade's
    // offset+length bounds check is IllegalArgumentException; a length below
    // digestLength or an out-of-range offset is DigestException. A failed
    // call does not consume the buffered input.
    for (args in listOf(intArrayOf(0, 10), intArrayOf(0, 31), intArrayOf(90, 20), intArrayOf(95, 10),
        intArrayOf(-1, 32), intArrayOf(0, -1), intArrayOf(0, 0), intArrayOf(69, 32), intArrayOf(60, 40))) {
        val md = MessageDigest.getInstance("SHAKE128")
        md.update("abc".encodeToByteArray())
        println("p|" + args[0] + "|" + args[1] + "|" + probeDigestOut(md, out, args[0], args[1]))
    }
    val afterFail = MessageDigest.getInstance("SHAKE128")
    afterFail.update("abc".encodeToByteArray())
    try {
        afterFail.digest(out, 0, 10)
    } catch (e: DigestException) {
    }
    println("af|" + hex(afterFail.digest()))

    // update(data, offset, length) bounds: past-the-end is
    // IllegalArgumentException, negative offset/length is an index error,
    // and a zero length never throws for the offset alone.
    val three = byteArrayOf(1, 2, 3)
    println("ub|" + probeUpdate(three, 0, 5))
    println("ub|" + probeUpdate(three, 100, 0))
    println("ub|" + probeUpdate(three, -2, 2))
    println("ub|" + probeUpdate(three, 0, -1))
    println("ub|" + probeUpdate(three, -5, 0))
    println("ub|" + probeUpdate(three, 1, 2))

    // Spellings the JDK rejects even though they fold to a supported name.
    for (name in listOf("SHAKE-128", "SHAKE-256", "SHAKE", "SHAKE128 ", "SHAKE128256",
        "SHAKE256-256", "SHAKE128-128", "SHA3-128", "Keccak-128")) {
        try {
            MessageDigest.getInstance(name)
            println(name + "|NO-THROW")
        } catch (e: NoSuchAlgorithmException) {
            println(name + "|" + e.message)
        }
    }
}
