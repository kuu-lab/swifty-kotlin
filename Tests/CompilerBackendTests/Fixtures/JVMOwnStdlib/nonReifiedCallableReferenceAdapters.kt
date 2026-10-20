import kotlin.coroutines.*

fun total(a: Int = 7, b: Int = 2): Int = a + b
fun <T> same(value: T, ignored: Int = 2): T = value
fun count(vararg values: String): Int = values.size
fun sum(vararg values: Int): Int { var result = 0; for (value in values) result += value; return result }
fun <T> pack(vararg values: T): Array<out T> = values
fun countArrays(vararg values: Array<String>): Int = values.size
fun countAny(vararg values: Any): Int = values.size
fun identity(value: Int): Int = value
fun Int.bump(delta: Int = 2): Int = this + delta
class Counter(val seed: Int = 40) { fun add(value: Int = 2): Int = seed + value }
open class Base { open fun value(n: Int = 3): Int = n }
class Derived: Base() { override fun value(n: Int): Int = n + 10 }
var evaluations = 0
fun owner(): Counter { evaluations++; return Counter() }
suspend fun load(value: Int = 5): Int = value + 1
fun launch(block: suspend () -> Int) {
    block.startCoroutine(object: Continuation<Int> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
    })
}
fun main() {
    val zero: () -> Int = ::total
    val partial: (Int) -> Int = ::total
    println(zero()); println(partial(40)); println(zero is kotlin.reflect.KFunction<*>)
    val bound: () -> Int = owner()::add
    println(evaluations); println(bound()); println(bound()); println(evaluations)
    val unbound: (Counter) -> Int = Counter::add
    println(unbound(Counter(10)))
    val constructor: () -> Counter = ::Counter
    println(constructor().seed)
    val extension: () -> Int = 40::bump
    val unboundExtension: (Int) -> Int = Int::bump
    println(extension()); println(unboundExtension(20))
    val inherited: () -> Int = Derived()::value
    println(inherited())
    val generic: (String) -> String = ::same
    println(generic("generic"))
    val unit: (Int, Int) -> Unit = ::total
    unit(1, 2); println(unit is kotlin.reflect.KFunction<*>)
    val empty: () -> Int = ::count
    val scalar: (String) -> Int = ::count
    val many: (String, String) -> Int = ::count
    val packed: (Array<String>) -> Int = ::count
    println(empty()); println(scalar("x")); println(many("x", "y")); println(packed(arrayOf("x", "y", "z")))
    val numbers: (Int, Int) -> Int = ::sum
    println(numbers(20, 22))
    val genericArray: (String) -> Array<out String> = ::pack
    val boxedArray: (Int) -> Array<out Int> = ::pack
    println(genericArray("x").javaClass.name); println(boxedArray(1).javaClass.name)
    val arrays: (Array<out Array<String>>) -> Int = ::countArrays
    println(arrays(arrayOf(arrayOf("x"))))
    val varargUnit: (String) -> Unit = ::count
    varargUnit("x"); println(varargUnit is kotlin.reflect.KFunction<*>)
    val converted: suspend () -> Int = ::total
    val suspending: suspend () -> Int = ::load
    println(converted is kotlin.reflect.KFunction<*>)
    launch(converted); launch(suspending)
    val packedUnit: (Array<Any>) -> Unit = ::countAny
    val scalarUnit: (Any) -> Unit = ::countAny
    val scalarUnitAgain: (Any) -> Unit = ::countAny
    println(packedUnit == scalarUnit)
    println(scalarUnit == scalarUnitAgain)
    println(packedUnit is kotlin.reflect.KFunction<*>)
    val direct: suspend (Int) -> Int = ::identity
    println(direct is kotlin.reflect.KFunction<*>)
    launch { direct(42) }
}
