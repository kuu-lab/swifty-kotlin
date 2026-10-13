import java.util.Locale

fun main() {
    val locale: Any = Locale("en", "US")
    println(locale is Locale)

    val typed = Locale("en", "US")
    println(typed is Locale)
    val language: Any = Locale("tr")
    println(language is Locale)

    val nullable: Any? = locale
    println(nullable is Locale)
    println(nullable is Locale?)
    val absent: Any? = null
    println(absent is Locale)
    println(absent is Locale?)

    val other: Any = "en_US"
    println(other is Locale)
    println(other !is Locale)
    println(other as? Locale == null)
    println(absent as? Locale == null)
    println(locale as? Locale === locale)
    println(language as? Locale === language)
    println(nullable as? Locale === locale)
    println(locale as Locale === locale)
    println((locale as Locale).toString())
    try {
        other as Locale
        println("unexpected cast")
    } catch (e: ClassCastException) {
        println("bad cast")
    }

    val values: List<Any?> = listOf(locale, language, other, null)
    for (value in values) {
        println(value is Locale)
    }
    println(values.filterIsInstance<Locale>().size)
    println(Locale::class.isInstance(locale))
    println(Locale::class.isInstance(other))
}
