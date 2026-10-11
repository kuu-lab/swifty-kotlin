import java.util.Locale
import kotlin.reflect.KFunction

inline fun <reified A, reified B> typedPair(supplier: () -> Array<B> = { emptyArray<B>() }): Pair<Array<A>, Array<B>> = Pair(emptyArray<A>(), supplier())
fun firstTypedWords(vararg values: String): Int = values.size
fun secondTypedWords(vararg values: Array<String>): Int = values.size
open class VirtualWords { open fun take(vararg values: String): String = "base:" + values.size }
class DerivedWords : VirtualWords() { override fun take(vararg values: String): String = "derived:" + values.size }

fun main() {
    val pair = typedPair<String, Array<String>>()
    val first = ::firstTypedWords
    val second = ::secondTypedWords
    println("two-t-first:" + first.callBy(mapOf(first.parameters[0] to pair.first)))
    println("two-t-second:" + second.callBy(mapOf(second.parameters[0] to pair.second)))
    val receiver: VirtualWords = DerivedWords()
    val scalar: (String) -> String = receiver::take
    val packed: (Array<out String>) -> String = receiver::take
    println("virtual-scalar:" + scalar("x"))
    println("virtual-packed:" + packed(arrayOf("x", "y")))
    val bound = receiver::take
    println("virtual-bound-omitted:" + bound.callBy(emptyMap()))
    val unbound = VirtualWords::take
    println("virtual-unbound-packed:" + unbound.callBy(mapOf(unbound.parameters[0] to receiver, unbound.parameters[1] to arrayOf("u"))))
    val locale: Locale? = null
    println("format-null-extension:" + "%s".format(locale, "extension-null"))
    println("format-null-companion:" + String.format(locale, "%s", "companion-null"))
}
