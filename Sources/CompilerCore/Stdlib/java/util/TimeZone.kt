package java.util

import kotlin.internal.KsSymbolName

/** A platform time zone used by the bundled java.util date APIs. */
public class TimeZone internal constructor(internal val rawHandle: Long) {
    public fun getID(): String = timeZoneGetID(rawHandle)

    public fun getRawOffset(): Int = timeZoneGetRawOffset(rawHandle)

    public fun getOffset(epochMilliseconds: Long): Int = timeZoneGetOffset(rawHandle, epochMilliseconds)

    /**
     * JVM `useDaylightTime`: whether this zone observes daylight saving time.
     * Probes the raw offset at two instants half a year apart — every zone
     * that observes DST reports different offsets across a solstice, and
     * zones that never observe DST report a constant offset. Zones whose
     * observance falls entirely outside the probed year under-report, a
     * documented approximation for the bundled shim.
     */
    public fun useDaylightTime(): Boolean {
        val now = Date().getTime()
        val halfYearMillis = 182L * 24L * 60L * 60L * 1000L
        return getOffset(now) != getOffset(now - halfYearMillis)
    }

    public val id: String
        get() = getID()

    public val rawOffset: Int
        get() = getRawOffset()

    public companion object {
        public fun getDefault(): TimeZone = TimeZone(timeZoneGetDefault())

        public fun getTimeZone(id: String): TimeZone = TimeZone(timeZoneFromID(id))
    }
}

@KsSymbolName("__kk_time_zone_get_default")
private external fun timeZoneGetDefault(): Long

@KsSymbolName("__kk_time_zone_get_time_zone")
private external fun timeZoneFromID(id: String): Long

@KsSymbolName("__kk_time_zone_get_id")
private external fun timeZoneGetID(timeZoneRaw: Long): String

@KsSymbolName("__kk_time_zone_get_raw_offset")
private external fun timeZoneGetRawOffset(timeZoneRaw: Long): Int

@KsSymbolName("__kk_time_zone_get_offset")
private external fun timeZoneGetOffset(timeZoneRaw: Long, epochMilliseconds: Long): Int
