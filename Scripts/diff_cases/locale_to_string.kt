import java.util.Locale

fun main() {
    println(Locale("en", "US"))
    println(Locale("tr", "TR"))
    println(Locale("EN", "us").toString())
    println(Locale("en", "").toString())
    println(Locale("", "us").toString())
    println("root=[${Locale("", "")}]")
    println(Locale("EN").toString())
    println(Locale("en_US").toString())
    println(Locale("en_US", "gb").toString())

    val locale: Any = Locale("en", "US")
    val nullable: Any? = Locale("tr", "TR")
    println(locale)
    println(locale.toString())
    println(nullable.toString())
    println("locale=$locale")
    println(listOf(locale, nullable))
    println(listOf(locale, nullable).joinToString("|"))
    println("%s".format(locale))
}
