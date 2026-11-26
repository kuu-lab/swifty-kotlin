package java.time

import java.util.TimeZone

public abstract class ZoneId internal constructor() {
    public abstract val id: String

    public fun getId(): String = id

    internal abstract fun javaTimeOffsetAt(epochSecond: Long): ZoneOffset

    public open fun normalized(): ZoneId = this

    override fun equals(other: Any?): Boolean =
        this !is ZoneOffset && other is ZoneId && other !is ZoneOffset && id == other.id

    override fun hashCode(): Int = id.hashCode()

    override fun toString(): String = id

    public companion object {
        public fun systemDefault(): ZoneId = JavaTimeRegionZoneId(TimeZone.getDefault())

        public fun of(zoneId: String): ZoneId {
            if (zoneId.length <= 1 || zoneId.startsWith("+") || zoneId.startsWith("-")) {
                return ZoneOffset.of(zoneId)
            }
            if (zoneId.startsWith("UTC") || zoneId.startsWith("GMT")) {
                return javaTimeZoneIdWithPrefix(zoneId, 3)
            }
            if (zoneId.startsWith("UT")) {
                return javaTimeZoneIdWithPrefix(zoneId, 2)
            }
            return javaTimeRegionZoneId(zoneId)
        }

        public fun ofOffset(prefix: String, offset: ZoneOffset): ZoneId {
            if (prefix.isEmpty()) {
                return offset
            }
            if (prefix != "GMT" && prefix != "UTC" && prefix != "UT") {
                throw IllegalArgumentException("prefix should be GMT, UTC or UT, is: " + prefix)
            }
            return JavaTimeOffsetZoneId(if (offset.totalSeconds != 0) prefix + offset.id else prefix, offset)
        }
    }
}

private class JavaTimeOffsetZoneId(
    private val zoneId: String,
    private val offset: ZoneOffset,
) : ZoneId() {
    override val id: String
        get() = zoneId

    override fun javaTimeOffsetAt(epochSecond: Long): ZoneOffset = offset

    override fun normalized(): ZoneId = offset
}

private class JavaTimeRegionZoneId(
    private val timeZone: TimeZone,
) : ZoneId() {
    override val id: String
        get() = timeZone.id

    override fun javaTimeOffsetAt(epochSecond: Long): ZoneOffset =
        ZoneOffset.ofTotalSeconds((timeZone.getOffset(epochSecond * 1_000L) / 1_000L).toInt())
}

private fun javaTimeZoneIdWithPrefix(zoneId: String, prefixLength: Int): ZoneId {
    val prefix = zoneId.substring(0, prefixLength)
    if (zoneId.length == prefixLength) {
        return ZoneId.ofOffset(prefix, ZoneOffset.UTC)
    }
    if (zoneId[prefixLength] != '+' && zoneId[prefixLength] != '-') {
        return javaTimeRegionZoneId(zoneId)
    }
    val offset = try {
        ZoneOffset.of(zoneId.substring(prefixLength))
    } catch (error: DateTimeException) {
        throw DateTimeException("Invalid ID for offset-based ZoneId: " + zoneId)
    }
    return ZoneId.ofOffset(prefix, offset)
}

private fun javaTimeRegionZoneId(zoneId: String): ZoneId {
    val timeZone = TimeZone.getTimeZone(zoneId)
    // The platform zone lookup falls back to GMT for IDs it does not know;
    // treat that as unknown unless the caller asked for GMT explicitly.
    if (timeZone.id == "GMT" && zoneId != "GMT") {
        throw DateTimeException("Unknown time-zone ID: " + zoneId)
    }
    return JavaTimeRegionZoneId(timeZone)
}
