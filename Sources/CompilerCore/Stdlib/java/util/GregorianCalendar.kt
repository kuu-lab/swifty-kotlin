package java.util

import kotlin.internal.KsSymbolName

public class GregorianCalendar : Calendar {
    public constructor() : super(TimeZone.getDefault())

    public constructor(timeZone: TimeZone) : super(timeZone)

    public constructor(year: Int, month: Int, day: Int) : this(year, month, day, 0, 0, 0)

    public constructor(year: Int, month: Int, day: Int, hourOfDay: Int, minute: Int) :
        this(year, month, day, hourOfDay, minute, 0)

    public constructor(year: Int, month: Int, day: Int, hourOfDay: Int, minute: Int, second: Int) :
        super(
            calendarCreateFields(
                TimeZone.getDefault().rawHandle,
                year,
                month,
                day,
                hourOfDay,
                minute,
                second
            )
        )

    public fun isLeapYear(year: Int): Boolean =
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

    public companion object {
        public const val BC: Int = 0
        public const val AD: Int = 1
    }
}

@KsSymbolName("__kk_calendar_create_fields")
private external fun calendarCreateFields(
    timeZoneRaw: Long,
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int
): Long
