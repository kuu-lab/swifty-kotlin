import java.util.Calendar
import java.util.GregorianCalendar

// KUU-4444: week-field writes (WEEK_OF_YEAR / WEEK_OF_MONTH / DAY_OF_WEEK /
// DAY_OF_WEEK_IN_MONTH) and setWeekDate must resolve like java.util.Calendar
// instead of silently no-oping. Field values are printed rather than
// Calendar.time because java.util.Date.toString is not implemented.

fun dump(cal: Calendar, label: String) {
    println(
        "$label y=${cal.get(Calendar.YEAR)} m=${cal.get(Calendar.MONTH)} " +
            "d=${cal.get(Calendar.DATE)} woy=${cal.get(Calendar.WEEK_OF_YEAR)} " +
            "wom=${cal.get(Calendar.WEEK_OF_MONTH)} dow=${cal.get(Calendar.DAY_OF_WEEK)} " +
            "dowim=${cal.get(Calendar.DAY_OF_WEEK_IN_MONTH)}"
    )
}

fun main() {
    val cal = Calendar.getInstance()
    cal.set(2023, 5, 15)
    dump(cal, "base")
    cal.set(Calendar.WEEK_OF_YEAR, 30)
    dump(cal, "woy30")
    cal.set(2023, 5, 15)
    cal.set(Calendar.WEEK_OF_MONTH, 2)
    dump(cal, "wom2")
    cal.set(2023, 5, 15)
    cal.set(Calendar.DAY_OF_WEEK, 1)
    dump(cal, "dow1")
    cal.set(2023, 5, 15)
    cal.set(Calendar.DAY_OF_WEEK_IN_MONTH, 3)
    dump(cal, "dowim3")
    cal.setWeekDate(2024, 10, 3)
    dump(cal, "weekdate")
    cal.set(2021, 0, 15)
    cal.set(Calendar.WEEK_OF_YEAR, 53)
    dump(cal, "woy53")

    // Week-field groups compose: a DAY_OF_WEEK write resolves inside the
    // most recently written week group.
    cal.set(2023, 5, 15)
    cal.set(Calendar.WEEK_OF_MONTH, 2)
    cal.set(Calendar.DAY_OF_WEEK, 1)
    dump(cal, "wom2-dow1")
    cal.set(2023, 5, 15)
    cal.set(Calendar.WEEK_OF_YEAR, 30)
    cal.set(Calendar.DAY_OF_WEEK, 1)
    dump(cal, "woy30-dow1")
    cal.set(2023, 5, 15)
    cal.set(Calendar.DAY_OF_WEEK_IN_MONTH, 2)
    cal.set(Calendar.DAY_OF_WEEK, 1)
    dump(cal, "dowim2-dow1")

    // setWeekDate edge cases: week 53 rollover and week-year APIs.
    cal.setWeekDate(2020, 53, 6)
    dump(cal, "weekdate53")
    println("weekYear=${cal.getWeekYear()} weeks=${cal.getWeeksInWeekYear()} supported=${cal.isWeekDateSupported()}")

    // Time-of-day fields survive week-field writes.
    val timed = Calendar.getInstance()
    timed.set(2023, 5, 15, 13, 45, 30)
    timed.set(Calendar.WEEK_OF_MONTH, 4)
    println("time h=${timed.get(Calendar.HOUR_OF_DAY)} m=${timed.get(Calendar.MINUTE)} s=${timed.get(Calendar.SECOND)} d=${timed.get(Calendar.DATE)}")

    // GregorianCalendar shares the same week-field path.
    val greg = GregorianCalendar()
    greg.set(2021, 11, 31)
    greg.set(Calendar.WEEK_OF_YEAR, 1)
    dump(greg, "greg-woy1")

    try {
        cal.setWeekDate(2024, 1, 9)
    } catch (e: IllegalArgumentException) {
        println("iae=${e.message}")
    }
}
