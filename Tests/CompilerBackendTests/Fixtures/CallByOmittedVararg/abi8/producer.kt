import java.util.Locale
import kotlin.reflect.KFunction

inline fun <reified A, reified B> typedPair(supplier: () -> Array<B> = { emptyArray<B>() }): Pair<Array<A>, Array<B>> = Pair(emptyArray<A>(), supplier())
fun firstTypedWords(vararg values: String): Int = values.size
fun secondTypedWords(vararg values: Array<String>): Int = values.size
open class VirtualWords { open fun take(vararg values: String): String = "base:" + values.size }
class DerivedWords : VirtualWords() { override fun take(vararg values: String): String = "derived:" + values.size }
