import java.util.Locale

fun main() {
    val locale = Locale("en", "US")
    val nullableLocale: Locale? = null
    println("literal".format(Locale("en")))
    println("%s".format(Locale("en"), "x"))
    println("%s".format(nullableLocale, "nullable"))
    println("%s|%s".format(locale, "a", "b"))
    println("%s".format(null, "null"))
    println("%s".format("a"))
    println("%s|%s".format("a", "b"))
    println(String.format(locale, "%s", "companion"))
    println('a'.uppercase(locale))
    val erased: Any = locale
    println(erased === locale)
}
