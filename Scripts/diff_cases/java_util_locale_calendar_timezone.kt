import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

fun main() {
    println(Locale.US)
    println(Locale.JAPAN)
    println(Locale.ENGLISH)

    val japanese = Locale.forLanguageTag("ja-JP")
    println(japanese)
    println(japanese.toLanguageTag())
    println(Locale.US.getLanguage())
    println(Locale.US.getCountry())
    println(Locale.US.getDisplayName(Locale.ENGLISH))
    println(String.format(Locale.US, "%,.2f", 1234.5))
    println(Locale.getDefault().getLanguage().isNotEmpty())

    val utc = TimeZone.getTimeZone("UTC")
    println(utc.getID())
    println(utc.getRawOffset())

    val calendar = Calendar.getInstance(utc)
    calendar.setTimeInMillis(0L)
    println(calendar.get(Calendar.YEAR))
    println(calendar.get(Calendar.MONTH))
    println(calendar.get(Calendar.DAY_OF_MONTH))
    println(calendar.get(Calendar.DAY_OF_WEEK))
    println(calendar.getTimeZone().getID())
    calendar.add(Calendar.DAY_OF_MONTH, 1)
    println(calendar.getTimeInMillis())
}
