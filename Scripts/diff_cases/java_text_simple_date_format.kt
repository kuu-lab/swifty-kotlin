// KUU-4440: bundled java.text.SimpleDateFormat formatting surface.
// Covers pattern fields, quoted literals, applyPattern/toPattern, locale
// names via DateFormatSymbols, week-year 'Y', timezone 'z'/'Z'/'X',
// millisecond precision, parse round-trip, and illegal-pattern rejection.
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun main() {
    val d = Date(1700000000000L)

    println(SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(d))
    println(SimpleDateFormat("EEE, MMM d, yyyy", Locale.US).format(d))
    println(SimpleDateFormat("EEEE MMMM dd yyyy hh:mm:ss a", Locale.JAPANESE).format(d))
    println(SimpleDateFormat("D F w W u G", Locale.US).format(d))
    println(SimpleDateFormat("SSS", Locale.US).format(Date(5L)))
    println(SimpleDateFormat("SSSS", Locale.US).format(d))
    println(SimpleDateFormat("''y'' 'year' yy", Locale.US).format(d))
    println(SimpleDateFormat("'T'HH:mm:ss'Z'", Locale.US).format(d))
    println(SimpleDateFormat("H:m:s.SSS", Locale.US).format(d))
    println(SimpleDateFormat("KkHh", Locale.US).format(d))

    val f = SimpleDateFormat("HH:mm", Locale.US)
    f.applyPattern("mm:ss")
    println(f.toPattern())
    println(f.format(d))

    println(SimpleDateFormat("z", Locale.JAPANESE).format(d))
    println(SimpleDateFormat("zzzz", Locale.US).format(d))
    println(SimpleDateFormat("Z X XX XXX", Locale.US).format(d))
    println(SimpleDateFormat("YYYY ww G", Locale.US).format(Date(1672531200000L)))
    println(SimpleDateFormat("YYYY ww G", Locale.US).format(Date(1703980800000L)))

    println(SimpleDateFormat("EEEE MMMM", Locale.GERMANY).format(d))
    println(SimpleDateFormat("GGGG yy", Locale.JAPANESE).format(d))
    println(SimpleDateFormat("LLL LLLL", Locale.US).format(d))
    println(SimpleDateFormat("a", Locale.GERMANY).format(d))
    println(SimpleDateFormat("D 'of' F 'in' w", Locale.US).format(d))

    val parsed = SimpleDateFormat("yyyy-MM-dd", Locale.US).parse("2023-11-15")
    println(parsed.time)
    println(SimpleDateFormat("yyyy-MM-dd", Locale.US).format(parsed))

    try {
        SimpleDateFormat("e", Locale.US)
        println("no-throw")
    } catch (ex: IllegalArgumentException) {
        println("threw: ${ex.message}")
    }
    try {
        SimpleDateFormat("x", Locale.US)
        println("no-throw")
    } catch (ex: IllegalArgumentException) {
        println("threw: ${ex.message}")
    }
}
