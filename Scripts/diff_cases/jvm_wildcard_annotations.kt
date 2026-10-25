import kotlin.jvm.JvmSuppressWildcards
import kotlin.jvm.JvmWildcard

@JvmSuppressWildcards
class WildcardContainer {
    @JvmSuppressWildcards(false)
    fun values(): List<@JvmWildcard String> = listOf("value")
}

fun main() {
    println(JvmSuppressWildcards().suppress)
    println(JvmSuppressWildcards(false).suppress)
    println(JvmSuppressWildcards(suppress = true).suppress)
    println(JvmWildcard::class.qualifiedName)
    println(JvmSuppressWildcards::class.qualifiedName)
    println(WildcardContainer().values().first())
}
