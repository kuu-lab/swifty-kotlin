// KUU-3079: bundled java.util legacy classes must resolve and behave on the JVM-compatible surface.
import java.text.SimpleDateFormat
import java.util.*

fun main() {
    val vector = Vector<Int>()
    vector.add(7)
    println("vector=${vector[0]}:${vector.size}")

    val table = Hashtable<String, Int>()
    table["answer"] = 42
    val values: Enumeration<Int> = table.elements()
    println("hashtable=${table["answer"]}:${values.nextElement()}")

    val tokenizer = StringTokenizer("red,green,,blue", ",")
    print("tokens=${tokenizer.countTokens()}:")
    while (tokenizer.hasMoreTokens()) print("${tokenizer.nextToken()}|")
    println()

    val properties = Properties()
    properties.setProperty("mode", "legacy")
    println("properties=${properties.getProperty("mode")}")

    val enumeration: Enumeration<Int>? = null
    println("enumeration=${enumeration == null}")

    val optional = Optional.of(5)
    println("optional=${optional.isPresent()}:${optional.orElse(0)}:${Optional.empty<Int>().isEmpty()}")

    val currency = Currency.getInstance("USD")
    println("currency=${currency.currencyCode}:${currency.defaultFractionDigits}")

    val formatter: SimpleDateFormat = SimpleDateFormat("yyyy")
}
