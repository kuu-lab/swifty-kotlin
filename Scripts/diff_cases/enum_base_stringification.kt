import kotlin.reflect.KFunction

enum class E { A; override fun toString(): String = "display" }
fun exposed(): Enum<*> = E.A

var calls = 0
enum class Stateful {
    A { override fun toString(): String { calls += 1; return "entry-$calls" } },
    B;
    override fun toString(): String { calls += 1; return "base-$calls" }
}
enum class Plain { A }
fun stateful(): Enum<*> = Stateful.A
fun concrete(): Stateful = Stateful.A
fun render(value: Enum<*>): String = value.toString()
fun <T : Enum<T>> implicit(value: T): String = "$value"
data class Wrapper(val value: Enum<*>)
fun <T> erasedLambda(f: () -> T) { val value: Any? = f(); println(value) }
inline fun <reified T : Enum<T>> enumFactory(): () -> Array<T> = { enumValues<T>() }

fun main() {
    println(exposed())
    println(render(exposed()))
    val display: Any = exposed()
    println(display)
    val value = stateful()
    println(calls)
    println(value)
    println("$value")
    println("prefix:" + value)
    print(value)
    println()
    println(implicit(Stateful.B))
    println(Wrapper(value))
    val nullable: Enum<*>? = value
    println(nullable)
    println("$nullable")
    val absent: Enum<*>? = null
    println(absent)
    println("$absent")
    println(Plain.A as Enum<*>)
    erasedLambda { Stateful.A }
    val entries = enumFactory<Stateful>()()
    println(calls)
    println(entries.toList())
    val function: KFunction<Stateful> = ::concrete
    val reflected = function.call()
    println(calls)
    println(reflected as Any)
}
