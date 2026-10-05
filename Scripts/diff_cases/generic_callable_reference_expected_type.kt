fun <T> identity(value: T): T = value
fun <A, B> second(first: A, second: B): B = second
fun use(ref: (Int) -> Int): Int = ref(42)
fun returned(): (Int) -> Int = ::identity

fun choose(value: String): String = "wrong"
fun <T> choose(value: T): T = value
fun <T> prefer(value: T): T = value
fun prefer(value: Int): Int = value + 1

class Box<T> {
    fun <R> transform(value: R): R = value
}
class UnboundBox {
    fun <T> transform(value: T): T = value
}
fun <T> T.copy(): T = this
fun interface IntOp {
    fun apply(value: Int): Int
}
fun useOp(op: IntOp): Int = op.apply(42)

fun main() {
    val ref: (Int) -> Int = ::identity
    println(ref(42))
    val longRef: (Long) -> Long = ::identity
    println(longRef(Long.MIN_VALUE))
    val stringRef: (String) -> String = ::identity
    println(stringRef("hello"))
    val nullableRef: (Int?) -> Int? = ::identity
    println(nullableRef(null))
    println(nullableRef(7))
    val widerRef: (Int) -> Any = ::identity
    println(widerRef(8))
    println(use(::identity))
    println(returned()(9))
    val secondRef: (Int, String) -> String = ::second
    println(secondRef(1, "second"))
    val overload: (Int) -> Int = ::choose
    println(overload(10))
    val concrete: (Int) -> Int = ::prefer
    println(concrete(10))
    val box = Box<String>()
    val bound: (Int) -> Int = box::transform
    println(bound(12))
    val unbound: (UnboundBox, Int) -> Int = UnboundBox::transform
    println(unbound(UnboundBox(), 13))
    val extension: (String) -> String = String::copy
    println(extension("extension"))
    val value = "bound"
    val boundExtension: () -> String = value::copy
    println(boundExtension())
    val listRef: (List<Int>) -> List<Int> = ::identity
    println(listRef(listOf(21, 22)))
    println(useOp(::identity))
}
