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

    /** JDK `getMinimum`: structural minimum for the field (Gregorian bounds). */
    public fun getMinimum(field: Int): Int = calendarGetFieldMinimum(rawHandle, field)

    /** JDK `getMaximum`: structural maximum for the field (Gregorian bounds). */
    public fun getMaximum(field: Int): Int = calendarGetFieldMaximum(rawHandle, field)

    /** JDK `getGreatestMinimum`: highest possible minimum for the field. */
    public fun getGreatestMinimum(field: Int): Int = calendarGetFieldGreatestMinimum(rawHandle, field)

    /** JDK `getLeastMaximum`: lowest possible maximum for the field. */
    public fun getLeastMaximum(field: Int): Int = calendarGetFieldLeastMaximum(rawHandle, field)

    /** JDK `getActualMinimum`: minimum for the field at the current time value. */
    public fun getActualMinimum(field: Int): Int = calendarGetFieldActualMinimum(rawHandle, field)

    /**
     * JDK `getActualMaximum`: maximum for the field at the current time
     * value (e.g. days in the current month, leap-aware).
     */
    public fun getActualMaximum(field: Int): Int = calendarGetFieldActualMaximum(rawHandle, field)

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

    /** JVM synthetic property view of `getTimeZone()`/`setTimeZone(TimeZone)`. */
    public var timeZone: TimeZone
        get() = getTimeZone()
        set(value) = setTimeZone(value)

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

        public const val JANUARY: Int = 0
        public const val FEBRUARY: Int = 1
        public const val MARCH: Int = 2
        public const val APRIL: Int = 3
        public const val MAY: Int = 4
        public const val JUNE: Int = 5
        public const val JULY: Int = 6
        public const val AUGUST: Int = 7
        public const val SEPTEMBER: Int = 8
        public const val OCTOBER: Int = 9
        public const val NOVEMBER: Int = 10
        public const val DECEMBER: Int = 11
        public const val UNDECIMBER: Int = 12

        public const val SUNDAY: Int = 1
        public const val MONDAY: Int = 2
        public const val TUESDAY: Int = 3
        public const val WEDNESDAY: Int = 4
        public const val THURSDAY: Int = 5
        public const val FRIDAY: Int = 6
        public const val SATURDAY: Int = 7

        public const val AM: Int = 0
        public const val PM: Int = 1

        public const val ALL_STYLES: Int = 0
        public const val SHORT: Int = 1
        public const val LONG: Int = 2
        public const val NARROW_FORMAT: Int = 4
        public const val NARROW_STANDALONE: Int = 32772
        public const val SHORT_FORMAT: Int = 65537
        public const val LONG_FORMAT: Int = 65538
        public const val SHORT_STANDALONE: Int = 32769
        public const val LONG_STANDALONE: Int = 32770

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

@KsSymbolName("__kk_calendar_get_minimum")
private external fun calendarGetFieldMinimum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_maximum")
private external fun calendarGetFieldMaximum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_greatest_minimum")
private external fun calendarGetFieldGreatestMinimum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_least_maximum")
private external fun calendarGetFieldLeastMaximum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_actual_minimum")
private external fun calendarGetFieldActualMinimum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_actual_maximum")
private external fun calendarGetFieldActualMaximum(calendarRaw: Long, field: Int): Int

@KsSymbolName("__kk_calendar_get_time_zone")
private external fun calendarGetTimeZone(calendarRaw: Long): Long

@KsSymbolName("__kk_calendar_set_time_zone")
private external fun calendarSetTimeZone(calendarRaw: Long, timeZoneRaw: Long)
