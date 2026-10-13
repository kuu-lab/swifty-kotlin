// KUU-1934: Inapplicable factories must not prevent a valid SAM constructor.
// KOTLINC_FLAGS: -Xjdk-release=17
fun interface Fallback { fun apply(value: Char): Int }
fun Fallback(value: Int): Fallback = Fallback { it.code }

fun interface WrongArity { fun apply(value: Char): Int }
fun WrongArity(block: (String, String) -> Int): WrongArity = WrongArity { it.code }

fun interface Typed<T> { fun apply(value: T): Int }
object TypedChar : Typed<Char> { override fun apply(value: Char): Int = 11 }
fun Typed(block: (String) -> Int): Typed<Char> = TypedChar

fun interface Defaulted { fun apply(value: Char): Int }
object DefaultedChar : Defaulted { override fun apply(value: Char): Int = 12 }
fun Defaulted(value: Int = 0, block: (String) -> Int): Defaulted = DefaultedChar

fun interface Generic<T> { fun apply(value: T): Int }
object GenericChar : Generic<Char> { override fun apply(value: Char): Int = 13 }
fun <R> Generic(block: (String) -> R): Generic<Char> = GenericChar

fun interface BoundedBlock<T> { fun run(value: T): Int }
fun interface Bounded { fun apply(value: Char): Int }
object BoundedChar : Bounded { override fun apply(value: Char): Int = 14 }
fun <T : Number> Bounded(block: BoundedBlock<T>): Bounded = BoundedChar

fun length(value: String): Int = value.length

fun main() {
    println(Fallback { it.code }.apply('a'))
    println(WrongArity { it.code }.apply('a'))
    println(Typed<Char> { it.code }.apply('a'))
    println(Typed { c: Char -> c.code }.apply('a'))
    println(Typed(::length).apply('a'))
    println(Defaulted { it.length }.apply('a'))
    println(Defaulted(block = { it.length }).apply('a'))
    println(Generic { it.length }.apply('a'))
    println(Bounded { c: Char -> c.code }.apply('a'))
}
