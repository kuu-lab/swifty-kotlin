// KUU-1966: direct, erased, and container calls across singleton declaration shapes.
abstract class Converter<T : Any> {
    abstract fun conv(s: String): T
}
interface Echo<T> {
    fun echo(value: T): T
}
abstract class PlainConverter {
    abstract fun conv(s: String): String
}
enum class Choice { FIRST, SECOND }
class Converters {
    object Text : Converter<String>() {
        override fun conv(s: String) = s
    }
    object Number : Converter<Int>() {
        override fun conv(s: String) = s.toInt()
    }
    object Flag : Converter<Boolean>() {
        override fun conv(s: String) = s == "yes"
    }
    object EnumValue : Converter<Choice>() {
        override fun conv(s: String) = Choice.SECOND
    }
    object PairValue : Converter<Pair<String, Int>>() {
        override fun conv(s: String) = Pair(s, 7)
    }
    object TextEcho : Echo<String> {
        override fun echo(value: String) = value
    }
    object IntEcho : Echo<Int> {
        override fun echo(value: Int) = value + 1
    }
    object Plain : PlainConverter() {
        override fun conv(s: String) = s
    }
    class Nested : Converter<String>() {
        override fun conv(s: String) = s
    }
}
object TopText : Converter<String>() {
    override fun conv(s: String) = s
}
object OuterObject {
    object Text : Converter<String>() {
        override fun conv(s: String) = s
    }
}
class Parsed<T : Any>(val type: Converter<T>) {
    var value: T? = null
    fun save(s: String) { value = type.conv(s) }
}
fun <T : Any> convert(type: Converter<T>, s: String): T = type.conv(s)
fun main() {
    println(Converters.Text.conv("direct"))
    val text: Converter<String> = Converters.Text
    println(text.conv("base"))
    println(convert(Converters.Text, "generic"))
    val parsed = Parsed(Converters.Text)
    parsed.save("in.txt")
    println(parsed.value)
    val number: Converter<Int> = Converters.Number
    println(number.conv("42"))
    println(convert(Converters.Number, "43"))
    val flag: Converter<Boolean> = Converters.Flag
    println(flag.conv("yes"))
    println(convert(Converters.Flag, "no"))
    val enumValue: Converter<Choice> = Converters.EnumValue
    println(enumValue.conv("enum"))
    val pairValue: Converter<Pair<String, Int>> = Converters.PairValue
    val pair = pairValue.conv("pair")
    println("${pair.first}:${pair.second}")
    val echo: Echo<String> = Converters.TextEcho
    println(echo.echo("echo"))
    val intEcho: Echo<Int> = Converters.IntEcho
    println(intEcho.echo(7))
    val plain: PlainConverter = Converters.Plain
    println(plain.conv("plain"))
    val nested: Converter<String> = Converters.Nested()
    println(nested.conv("nested-class"))
    val top: Converter<String> = TopText
    println(top.conv("top"))
    val objectNested: Converter<String> = OuterObject.Text
    println(objectNested.conv("object-nested"))
}
