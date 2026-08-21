/*
 * Portions of this file (the generateV7()/generateV7NonMonotonicAt() UUID
 * version 7 generation algorithm) are derived from kotlin-stdlib
 * <commonMain/kotlin/uuid/Uuid.kt> (UuidV7Generator), Copyright 2010-2024
 * JetBrains s.r.o. and Kotlin Programming Language contributors, licensed
 * under the Apache License, Version 2.0.
 */
package kotlin.uuid

@file:OptIn(ExperimentalUuidApi::class)

import java.nio.ByteBuffer
import kotlin.internal.KsSymbolName
import kotlin.time.Instant
import kotlin.time.epochSeconds
import kotlin.time.nanosecondsOfSecond
import kotlin.time.now

private const val UUID_HEX_DIGITS: String = "0123456789abcdef"

/**
 * Represents a Universally Unique Identifier (UUID) as defined by RFC 9562.
 */
@ExperimentalUuidApi
public class Uuid private constructor(
    msb: Long,
    lsb: Long,
) : Comparable<Uuid> {
    @PublishedApi internal val mostSignificantBits: Long = msb
    @PublishedApi internal val leastSignificantBits: Long = lsb
    public companion object {
        public const val SIZE_BITS: Int = 128
        public const val SIZE_BYTES: Int = 16

        public val NIL: Uuid = fromLongs(0L, 0L)

        @Deprecated(
            "Use naturalOrder<Uuid>() instead",
            ReplaceWith("naturalOrder<Uuid>()", imports = ["kotlin.comparisons.naturalOrder"])
        )
        @DeprecatedSinceKotlin(warningSince = "2.1", errorSince = "2.4")
        public val LEXICAL_ORDER: Comparator<Uuid> = __kk_uuid_lexicalOrder()

        public fun random(): Uuid = __kk_uuid_random()

        public fun parse(uuidString: String): Uuid {
            val parsed = parseOrNull(uuidString)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID string: $uuidString")
            return parsed!!
        }

        public fun parseOrNull(uuidString: String): Uuid? =
            parseStringOrNull(uuidString)

        public fun parseHex(hexString: String): Uuid {
            val parsed = parseHexOrNull(hexString)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID hex string: $hexString")
            return parsed!!
        }

        public fun parseHexOrNull(hexString: String): Uuid? =
            parseHexBodyOrNull(hexString)

        public fun parseHexDash(hexDashString: String): Uuid {
            val hex = hexFromHexDashString(hexDashString)
            if (hex == null) throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            val parsed = parseHexBodyOrNull(hex!!)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            return parsed!!
        }

        public fun parseHexDashOrNull(hexDashString: String): Uuid? {
            val hex = hexFromHexDashString(hexDashString)
            if (hex == null) return null
            return parseHexBodyOrNull(hex!!)
        }

        public fun fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid =
            __kk_uuid_fromLongs(mostSignificantBits, leastSignificantBits)

        public fun fromULongs(mostSignificantBits: ULong, leastSignificantBits: ULong): Uuid =
            fromLongs(mostSignificantBits.toLong(), leastSignificantBits.toLong())

        public fun fromByteArray(byteArray: ByteArray): Uuid {
            if (byteArray.size != SIZE_BYTES) {
                throw IllegalArgumentException("byteArray.size must be 16, was ${byteArray.size}")
            }
            var msb = 0L
            var lsb = 0L
            var i = 0
            while (i < 8) {
                msb = (msb shl 8) or (byteArray[i].toLong() and 0xffL)
                i += 1
            }
            while (i < 16) {
                lsb = (lsb shl 8) or (byteArray[i].toLong() and 0xffL)
                i += 1
            }
            return Uuid(msb, lsb)
        }

        public fun fromUByteArray(ubyteArray: UByteArray): Uuid {
            if (ubyteArray.size != SIZE_BYTES) {
                throw IllegalArgumentException("ubyteArray.size must be 16, was ${ubyteArray.size}")
            }
            var msb = 0L
            var lsb = 0L
            var i = 0
            while (i < 8) {
                msb = (msb shl 8) or (ubyteArray[i].toLong() and 0xffL)
                i += 1
            }
            while (i < 16) {
                lsb = (lsb shl 8) or (ubyteArray[i].toLong() and 0xffL)
                i += 1
            }
            return Uuid(msb, lsb)
        }

        public fun generateV4(): Uuid = random()

        // Ported from kotlin-stdlib's UuidV7Generator (see file header for
        // attribution). Bit layout per RFC 9562 section-4.2:
        //   msb = unix_ts_ms(48) | ver(4)=0111 | rand_a/counter(12)
        //   lsb = var(2)=10 | rand_b(62)
        // Randomness is drawn from random()'s existing secure entropy bridge
        // (__kk_uuid_random) rather than a new bridge; only the fixed
        // version/variant bit positions of that v4 source are avoided when
        // slicing bits out, so the reused entropy stays uniformly random.
        //
        // Deviation from upstream (tracked in docs/stdlib-pipeline.md §13-8):
        // upstream uses a CAS loop over an AtomicLong for thread-safe
        // monotonicity; this port uses a plain var since kswiftc's
        // diff/golden harness is single-threaded. Resolution condition:
        // adopt kotlin.concurrent.atomics.AtomicLong once its load()/
        // compareAndSet() are verified working end-to-end.
        private val v7State: UuidV7MonotonicState = UuidV7MonotonicState()

        public fun generateV7(): Uuid {
            val entropy = random()
            val seedCounter = ((entropy.mostSignificantBits ushr 53).toInt() and 0x7FF) or 0x7000
            val nowMillis = run {
                val now = Instant.now()
                now.epochSeconds * 1000L + (now.nanosecondsOfSecond / 1_000_000).toLong()
            }
            val previous = v7State.timestampAndCounter
            val previousMillis = previous ushr 16
            val updated = if (previousMillis < nowMillis) {
                (nowMillis shl 16) or seedCounter.toLong()
            } else {
                val incremented = previous + 1L
                if ((incremented and 0x8000L) != 0L) {
                    ((previousMillis + 1L) shl 16) or seedCounter.toLong()
                } else {
                    incremented
                }
            }
            v7State.timestampAndCounter = updated

            val randB = entropy.leastSignificantBits and ((1L shl 62) - 1L)
            val variantAndRandB = (0x2L shl 62) or randB
            return fromLongs(updated, variantAndRandB)
        }

        // See generateV7() above for bit-layout and entropy-reuse notes.
        // Unlike generateV7(), this is a pure function of [timestamp] with no
        // shared state, so repeated calls with the same timestamp are not
        // guaranteed to sort in call order (hence "NonMonotonic").
        public fun generateV7NonMonotonicAt(timestamp: Instant): Uuid {
            val entropy = random()
            val randA = (entropy.mostSignificantBits ushr 52).toInt() and 0xFFF
            val unixTsMs = timestamp.epochSeconds * 1000L + (timestamp.nanosecondsOfSecond / 1_000_000).toLong()
            val tsVerAndRandA = (unixTsMs shl 16) or (0x7000L or randA.toLong())

            val randB = entropy.leastSignificantBits and ((1L shl 62) - 1L)
            val variantAndRandB = (0x2L shl 62) or randB
            return fromLongs(tsVerAndRandA, variantAndRandB)
        }

        private fun parseStringOrNull(uuidString: String): Uuid? {
            if (uuidString.length == 36) {
                val hex = hexFromHexDashString(uuidString)
                if (hex == null) return null
                return parseHexBodyOrNull(hex!!)
            }
            if (uuidString.length == 32) {
                return parseHexBodyOrNull(uuidString)
            }
            return null
        }

        private fun parseHexBodyOrNull(hex: String): Uuid? {
            if (hex.length != 32) return null
            var msb = 0L
            var lsb = 0L
            var i = 0
            while (i < 16) {
                val digit = hexDigit(hex[i])
                if (digit < 0) return null
                msb = (msb shl 4) or digit.toLong()
                i += 1
            }
            while (i < 32) {
                val digit = hexDigit(hex[i])
                if (digit < 0) return null
                lsb = (lsb shl 4) or digit.toLong()
                i += 1
            }
            return Uuid(msb, lsb)
        }

        private fun hexFromHexDashString(hexDashString: String): String? {
            if (hexDashString.length != 36) return null
            val sb = StringBuilder()
            var i = 0
            while (i < 36) {
                val ch = hexDashString[i]
                if (i == 8 || i == 13 || i == 18 || i == 23) {
                    if (ch != '-') return null
                } else {
                    if (hexDigit(ch) < 0) return null
                    sb.append(ch)
                }
                i += 1
            }
            return sb.toString()
        }

        private fun hexDigit(ch: Char): Int {
            if (ch >= '0' && ch <= '9') return ch.code - '0'.code
            if (ch >= 'a' && ch <= 'f') return ch.code - 'a'.code + 10
            if (ch >= 'A' && ch <= 'F') return ch.code - 'A'.code + 10
            return -1
        }

    }

    public override fun toString(): String {
        val sb = StringBuilder()
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        appendHex(sb, msb ushr 32, 8)
        sb.append('-')
        appendHex(sb, msb ushr 16, 4)
        sb.append('-')
        appendHex(sb, msb, 4)
        sb.append('-')
        appendHex(sb, lsb ushr 48, 4)
        sb.append('-')
        appendHex(sb, lsb, 12)
        return sb.toString()
    }

    public fun toHexString(): String {
        val sb = StringBuilder()
        appendHex(sb, mostSignificantBits, 16)
        appendHex(sb, leastSignificantBits, 16)
        return sb.toString()
    }

    public fun toHexDashString(): String = toString()

    public inline fun <T> toLongs(action: (Long, Long) -> T): T =
        action(mostSignificantBits, leastSignificantBits)

    public inline fun <T> toULongs(action: (ULong, ULong) -> T): T =
        action(mostSignificantBits.toULong(), leastSignificantBits.toULong())

    public fun toByteArray(): ByteArray {
        val bytes = ByteArray(SIZE_BYTES) { 0 }
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        var i = 0
        while (i < 8) {
            bytes[i] = ((msb ushr (56 - i * 8)) and 0xffL).toByte()
            i += 1
        }
        while (i < 16) {
            bytes[i] = ((lsb ushr (56 - (i - 8) * 8)) and 0xffL).toByte()
            i += 1
        }
        return bytes
    }

    public fun toUByteArray(): UByteArray {
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        return UByteArray(SIZE_BYTES) { i ->
            val shift = 56 - (if (i < 8) i else i - 8) * 8
            val value = if (i < 8) (msb ushr shift) and 0xffL else (lsb ushr shift) and 0xffL
            value.toUByte()
        }
    }

    public override fun compareTo(other: Uuid): Int {
        val msbSelf = mostSignificantBits.toULong()
        val msbOther = other.mostSignificantBits.toULong()
        if (msbSelf != msbOther) return if (msbSelf < msbOther) -1 else 1
        val lsbSelf = leastSignificantBits.toULong()
        val lsbOther = other.leastSignificantBits.toULong()
        if (lsbSelf != lsbOther) return if (lsbSelf < lsbOther) -1 else 1
        return 0
    }

    public override fun equals(other: Any?): Boolean {
        if (other !is Uuid) return false
        // Explicit re-cast: `is`-checks do not smart-cast in bundled source yet.
        val that = other as Uuid
        return mostSignificantBits == that.mostSignificantBits &&
            leastSignificantBits == that.leastSignificantBits
    }

    public override fun hashCode(): Int {
        val hilo = mostSignificantBits xor leastSignificantBits
        return ((hilo ushr 32) xor hilo).toInt()
    }

    private fun appendHex(sb: StringBuilder, value: Long, digits: Int) {
        var shift = (digits - 1) * 4
        while (shift >= 0) {
            val digit = ((value ushr shift) and 0x0fL).toInt()
            sb.append(UUID_HEX_DIGITS[digit])
            shift -= 4
        }
    }
}

// Holds Uuid.Companion's monotonic generateV7() state: the last-used
// (timestamp << 16 | version | counter) value, packed identically to a v7
// uuid's own msb so it can be reused as one directly. See generateV7()'s
// doc comment for why this is a plain var rather than an AtomicLong.
internal class UuidV7MonotonicState {
    var timestampAndCounter: Long = 0L
}

@KsSymbolName("__kk_uuid_random")
private external fun __kk_uuid_random(): Uuid

@KsSymbolName("__kk_uuid_fromLongs")
private external fun __kk_uuid_fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid

@KsSymbolName("__kk_uuid_lexicalOrder")
private external fun __kk_uuid_lexicalOrder(): Comparator<Uuid>

// java.util.UUID interop needs a native bridge to read a foreign UUID
// representation; every other kotlin.uuid extension below is pure Kotlin
// built on top of Uuid's own mostSignificantBits/leastSignificantBits/fromLongs.
@KsSymbolName("__kk_uuid_toKotlinUuid")
private external fun __kk_uuid_toKotlinUuid(receiver: java.util.UUID): Uuid

@kotlin.uuid.ExperimentalUuidApi
public fun java.util.UUID.toKotlinUuid(): Uuid = __kk_uuid_toKotlinUuid(this)

private fun readUuidFromByteBuffer(buffer: ByteBuffer, offset: Int): Uuid {
    if (offset < 0 || offset + 15 >= buffer.limit()) {
        throw IndexOutOfBoundsException(
            "offset $offset is out of bounds for buffer of limit ${buffer.limit()}"
        )
    }
    var msb = 0L
    var i = 0
    while (i < 8) {
        msb = (msb shl 8) or (buffer.get(offset + i).toLong() and 0xFFL)
        i += 1
    }
    var lsb = 0L
    i = 8
    while (i < 16) {
        lsb = (lsb shl 8) or (buffer.get(offset + i).toLong() and 0xFFL)
        i += 1
    }
    return Uuid.fromLongs(msb, lsb)
}

private fun writeUuidToByteBuffer(buffer: ByteBuffer, offset: Int, uuid: Uuid) {
    val msb = uuid.mostSignificantBits
    val lsb = uuid.leastSignificantBits
    var i = 0
    while (i < 8) {
        buffer.put(offset + i, ((msb ushr (56 - i * 8)) and 0xFFL).toByte())
        i += 1
    }
    i = 0
    while (i < 8) {
        buffer.put(offset + 8 + i, ((lsb ushr (56 - i * 8)) and 0xFFL).toByte())
        i += 1
    }
}

@kotlin.uuid.ExperimentalUuidApi
public fun ByteBuffer.getUuid(): Uuid {
    val p = position()
    if (p + 15 >= limit()) {
        throw IndexOutOfBoundsException(
            "position $p is out of bounds for buffer of limit ${limit()}"
        )
    }
    val uuid = readUuidFromByteBuffer(this, p)
    position(p + 16)
    return uuid
}

@kotlin.uuid.ExperimentalUuidApi
public fun ByteBuffer.getUuid(index: Int): Uuid = readUuidFromByteBuffer(this, index)

@kotlin.uuid.ExperimentalUuidApi
public fun ByteBuffer.putUuid(uuid: Uuid): ByteBuffer {
    val p = position()
    if (p + 15 >= limit()) {
        throw IndexOutOfBoundsException(
            "position $p is out of bounds for buffer of limit ${limit()}"
        )
    }
    writeUuidToByteBuffer(this, p, uuid)
    position(p + 16)
    return this
}

@kotlin.uuid.ExperimentalUuidApi
public fun ByteBuffer.putUuid(index: Int, uuid: Uuid): ByteBuffer {
    writeUuidToByteBuffer(this, index, uuid)
    return this
}
