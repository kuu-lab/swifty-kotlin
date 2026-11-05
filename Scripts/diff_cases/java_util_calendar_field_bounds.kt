import java.util.Calendar
import java.util.GregorianCalendar

// KUU-4288: java.util.Calendar field-bound family — getMinimum / getMaximum /
// getGreatestMinimum / getLeastMaximum / getActualMinimum / getActualMaximum.
// Bounds are date-independent; actual bounds depend on the current field
// values (leap-aware DAY_OF_MONTH/DAY_OF_YEAR, week-rule-sensitive
// WEEK_OF_YEAR/WEEK_OF_MONTH, state-dependent YEAR).

val fields = intArrayOf(
    Calendar.ERA, Calendar.YEAR, Calendar.MONTH, Calendar.WEEK_OF_YEAR,
    Calendar.WEEK_OF_MONTH, Calendar.DAY_OF_MONTH, Calendar.DAY_OF_YEAR,
    Calendar.DAY_OF_WEEK, Calendar.DAY_OF_WEEK_IN_MONTH, Calendar.AM_PM,
    Calendar.HOUR, Calendar.HOUR_OF_DAY, Calendar.MINUTE, Calendar.SECOND,
    Calendar.MILLISECOND, Calendar.ZONE_OFFSET, Calendar.DST_OFFSET
)

fun dumpBounds(cal: Calendar) {
    for (f in fields) {
        println("f=$f min=${cal.getMinimum(f)} max=${cal.getMaximum(f)} gmin=${cal.getGreatestMinimum(f)} lmax=${cal.getLeastMaximum(f)}")
    }
}

fun dumpActual(cal: Calendar, label: String) {
    for (f in fields) {
        println("$label f=$f amin=${cal.getActualMinimum(f)} amax=${cal.getActualMaximum(f)}")
    }
}

fun main() {
    val cal = GregorianCalendar(1969, 3, 1)
    dumpBounds(cal)
    dumpActual(cal, "1969-04-01")
    dumpActual(GregorianCalendar(2024, 1, 15, 12, 30, 45), "2024-02-15")
    dumpActual(GregorianCalendar(2023, 1, 15, 12, 30, 45), "2023-02-15")
    dumpActual(GregorianCalendar(2022, 0, 15), "2022-01-15")
    dumpActual(GregorianCalendar(2023, 11, 31), "2023-12-31")
    dumpActual(GregorianCalendar(2024, 11, 31, 23, 59, 59), "2024-12-31")

    // Rosetta-style usage from the ticket: days-in-month + offset.
    val date = GregorianCalendar(1969, 3, 1)
    val dim = date.getActualMaximum(Calendar.DAY_OF_MONTH)
    val offs = 7
    println("dim=$dim offs+dim=${offs + dim}")
}
