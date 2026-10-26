package java.util

import kotlin.internal.KsSymbolName

/** A Gregorian calendar backed by the runtime's platform date implementation. */
public open class Calendar internal constructor(private val rawHandle: Long) {
    internal constructor(timeZone: TimeZone) : this(calendarCreate(timeZone.rawHandle))

    public fun getTimeInMillis(): Long = calendarGetTimeInMillis(rawHandle)

    public fun setTimeInMillis(value: Long) {
        calendarSetTimeInMillis(rawHandle, value)
    }

    public fun getTime(): Date = Date(getTimeInMillis())

    public fun setTime(value: Date) {
        setTimeInMillis(value.getTime())
    }

    public fun get(field: Int): Int = calendarGetField(rawHandle, field)

    public fun set(field: Int, value: Int) {
        calendarSetField(rawHandle, field, value)
    }

    public fun add(field: Int, amount: Int) {
        calendarAddField(rawHandle, field, amount)
    }

    public fun getTimeZone(): TimeZone = TimeZone(calendarGetTimeZone(rawHandle))

    public fun setTimeZone(timeZone: TimeZone) {
        calendarSetTimeZone(rawHandle, timeZone.rawHandle)
    }

    public var timeInMillis: Long
        get() = getTimeInMillis()
        set(value) = setTimeInMillis(value)

    public var time: Date
        get() = getTime()
        set(value) = setTime(value)

    public companion object {
        public const val ERA: Int = 0
        public const val YEAR: Int = 1
        public const val MONTH: Int = 2
        public const val WEEK_OF_YEAR: Int = 3
        public const val WEEK_OF_MONTH: Int = 4
        public const val DATE: Int = 5
        public const val DAY_OF_MONTH: Int = 5
        public const val DAY_OF_YEAR: Int = 6
        public const val DAY_OF_WEEK: Int = 7
        public const val DAY_OF_WEEK_IN_MONTH: Int = 8
        public const val AM_PM: Int = 9
        public const val HOUR: Int = 10
        public const val HOUR_OF_DAY: Int = 11
        public const val MINUTE: Int = 12
        public const val SECOND: Int = 13
        public const val MILLISECOND: Int = 14
        public const val ZONE_OFFSET: Int = 15
        public const val DST_OFFSET: Int = 16
        public const val FIELD_COUNT: Int = 17

        public fun getInstance(): Calendar = Calendar(calendarCreate(TimeZone.getDefault().rawHandle))

        public fun getInstance(timeZone: TimeZone): Calendar = Calendar(calendarCreate(timeZone.rawHandle))
    }
}

@KsSymbolName("__kk_calendar_create")
private external fun calendarCreate(timeZoneRaw: Long): Long

@KsSymbolName("__kk_calendar_get_time_in_millis")
private external fun calendarGetTimeInMillis(calendarRaw: Long): Long

@KsSymbolName("__kk_calendar_set_time_in_millis")
private external fun calendarSetTimeInMillis(calendarRaw: Long, value: Long)

@KsSymbolName("__kk_calendar_get_field")
private external fun calendarGetField(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_set_field")
private external fun calendarSetField(calendarRaw: Long, field: Int, value: Int)

@KsSymbolName("__kk_calendar_add_field")
private external fun calendarAddField(calendarRaw: Long, field: Int, amount: Int)

@KsSymbolName("__kk_calendar_get_time_zone")
private external fun calendarGetTimeZone(calendarRaw: Long): Long

@KsSymbolName("__kk_calendar_set_time_zone")
private external fun calendarSetTimeZone(calendarRaw: Long, timeZoneRaw: Long)
