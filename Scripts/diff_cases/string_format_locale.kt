import java.util.Locale

fun main() {
    println(String.format(Locale("en", "US"), "%s:%d", "age", 7))
    println(String.format(Locale("de", "DE"), "%,d", 1234567))
    println(String.format(Locale("en", "US"), "%,d", 1234567))
    println(String.format(Locale("en", "US"), "%,d", -1234567))
    println(String.format(Locale("en", "US"), "%,012d", 1234))
    println(String.format(Locale("de", "DE"), "%,.2f", 1234.5))
    println(String.format(Locale("en", "US"), "%,.2f", 1234.5))
    println("%,d".format(9876543))
    println(String.format("%s-%d", "id", 42))
    // No grouping flag: a locale must not introduce separators on its own.
    println(String.format(Locale("en", "US"), "%d", 1234567))
    println(String.format(Locale("de", "DE"), "%d", 1234567))
    println(String.format(Locale("en", "US"), "%012d", 1234))
    println(String.format(Locale("de", "DE"), "%.2f", 1234.5))
}
