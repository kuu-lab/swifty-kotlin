import java.util.Calendar
import java.util.GregorianCalendar
import java.util.TimeZone

fun main() {
    // KUU-4075: bundled java.util Calendar/GregorianCalendar/TimeZone —
    // isLeapYear, field constants, and the `timeZone` property view of
    // getTimeZone/setTimeZone used by Rosetta date tasks.
    println(GregorianCalendar().isLeapYear(2000))
    println(GregorianCalendar().isLeapYear(1900))
    println(GregorianCalendar().isLeapYear(2100))
    println(Calendar.FRIDAY)
    println(Calendar.SUNDAY)
    println(Calendar.SATURDAY)
    println(Calendar.JANUARY)
    println(Calendar.DECEMBER)
    println(Calendar.DAY_OF_WEEK)
    println(Calendar.MILLISECOND)

    val mst = TimeZone.getTimeZone("MST")
    println(mst.id)
    println(mst.rawOffset)
    println(mst.getOffset(0L))

    val cal = GregorianCalendar()
    cal.timeZone = mst
    println(cal.timeZone.id)
    println(cal.getTimeZone().id)
    cal.setTimeZone(TimeZone.getTimeZone("UTC"))
    println(cal.timeZone.id)

    val utcCal = GregorianCalendar(TimeZone.getTimeZone("UTC"))
    utcCal.setTimeInMillis(0L)
    println(utcCal.get(Calendar.YEAR))
    println(utcCal.get(Calendar.MONTH))
    println(utcCal.get(Calendar.DAY_OF_MONTH))
    println(utcCal.get(Calendar.DAY_OF_WEEK))
    println(utcCal.timeZone.id)
}
