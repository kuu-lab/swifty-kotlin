import java.util.Locale

fun main() {
    // KUU-1005: the parentheses flag must be parsed, not emitted literally.
    println("%(d".format(-42))
    println("%(d".format(42))
    println(String.format("%(d", -42))

    for (value in listOf(-42, 42, 0, Int.MIN_VALUE, Int.MAX_VALUE)) {
        for (template in listOf("%(d", "%(6d", "%-(6d", "%(06d", "%(3d", "%+(06d", "% (06d")) {
            println("[" + template.format(value) + "]")
        }
    }
    for (value in listOf(Long.MIN_VALUE, Long.MAX_VALUE, -1234567890123L, 0L)) {
        println("%(d|%<(025d|%<(,030d".format(value))
    }
    for (value in listOf(-1234, 1234, 0)) {
        println("%(,012d|%<-(,12d".format(value))
    }
    println("%2\$(d|%1\$(d|%<(06d".format(42, -42))

    for (value in listOf(-42.5, 42.5, -0.0, 0.0, Double.NEGATIVE_INFINITY, Double.POSITIVE_INFINITY, Double.NaN)) {
        for (template in listOf("%(010.2f", "%-(12.2f", "%(.2e", "%(.2E", "%(.4g", "%(.4G", "%(012f")) {
            println("[" + template.format(value) + "]")
        }
    }
    for (locale in listOf(Locale("en", "US"), Locale("de", "DE"))) {
        println(String.format(locale, "%(,012d|%(,012.2f", -1234, -1234.5))
        println(String.format(locale, "%(,012d|%(,012.2f", 1234, 1234.5))
    }
}
