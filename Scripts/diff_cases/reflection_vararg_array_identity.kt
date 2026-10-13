import kotlin.reflect.KFunction

val controlDefault: Array<String> = arrayOf("d", "e")
fun controlWords(vararg words: String = controlDefault): Array<out String> = words
fun controlInts(vararg values: Int): IntArray = values
fun controlNullable(vararg words: String?): Array<out String?> = words
fun <T> controlGeneric(vararg values: T): Array<out T> = values
fun <T : CharSequence> controlBound(vararg values: T): Array<out T> = values
class ControlCtor(vararg val words: String)
fun controlRejected(action: () -> Unit): String = try { action(); "OK" } catch (_: IllegalArgumentException) { "IAE" }

fun main() {
    val words = arrayOf("a", "b")
    val spread = controlWords(*words)
    println("spread-copy:${spread === words}")
    println("named-array:${controlWords(words = words) === words}")
    println("default-identity:${controlWords() === controlDefault}")
    val reflected = ::controlWords
    println("reflect-identity:${reflected.callBy(mapOf(reflected.parameters[0] to words)) === words}")
    println("reflect-default:${reflected.callBy(emptyMap()) === controlDefault}")
    val direct: (Array<out String>) -> Array<out String> = ::controlWords
    println("function-invoke:${direct(words) === words}")
    val ctor: (Array<out String>) -> ControlCtor = ::ControlCtor
    println("constructor-invoke:${ctor(words).words === words}")
    val ints = intArrayOf(1, 2)
    println("primitive-spread-copy:${controlInts(*ints) === ints}")
    println("primitive-named:${controlInts(values = ints) === ints}")
    val nullable = emptyArray<String?>()
    println("nullable-component:${(::controlNullable).callBy(mapOf((::controlNullable).parameters[0] to nullable)) === nullable}")
    val generic: KFunction<Array<out String>> = ::controlGeneric
    val wrongEmpty = emptyArray<Int>()
    println("generic-erasure:${generic.callBy(mapOf(generic.parameters[0] to wrongEmpty)) === wrongEmpty}")
    val bounded: KFunction<Array<out String>> = ::controlBound
    println("bound-reject:${controlRejected { bounded.callBy(mapOf(bounded.parameters[0] to wrongEmpty)) }}")
    println("bound-accept:${bounded.callBy(mapOf(bounded.parameters[0] to words)) === words}")
    val emptyWords = emptyArray<String>()
    println("empty-copy-component:${controlRejected { (::controlInts).callBy(mapOf((::controlInts).parameters[0] to emptyWords.copyOf())) }}")
    println("array-list:${words.asList().size}:${words.asList()[1]}")
    println("direct-values:${controlWords("x", "y").joinToString()}")
}
