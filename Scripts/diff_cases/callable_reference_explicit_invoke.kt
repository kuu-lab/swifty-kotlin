// KUU-1723: explicit invocation uses the reference's function signature.
fun add(a: Int, b: Int): Int = a + b
fun subtract(a: Int, b: Int): Int = a - b
fun zero(): Int = 12
fun Int.bump(delta: Int): Int = this + delta
fun <T> identity(value: T): T = value
fun apply(block: () -> Int): Int = block()
fun applyOne(block: (Int) -> Int): Int = block(14)
fun applyAt(value: Int, block: () -> Int): Int = value + block()
fun asByte(value: Byte): Int = value.toInt()
fun inferredReference() = ::add
fun inferredHigherOrderReference() = ::applyOne
fun forwardReference() = ::applyLater
fun applyLater(block: (Int) -> Int): Int = block(20)
inline fun explicitInline(block: (Int) -> Int): Int = block(30)
fun nullableReference(present: Boolean) = if (present) ::add else null
class Counter(val seed: Int) {
    fun add(value: Int): Int = seed + value
    fun applyMapped(block: (Int) -> Int): Int = block(seed)
}
class Operator {
    operator fun invoke(value: Int): Int = value + 20
}

fun main() {
    val reference = ::add
    println(reference.invoke(3, 4))
    println(reference(3, 4))
    println(reference.name)
    println(reference.call(3, 4))
    var changing = ::add
    changing = ::subtract
    println(changing.invoke(9, 4))
    val bound = Counter(10)::add
    val unbound = Counter::add
    println(bound.invoke(2))
    println(unbound.invoke(Counter(10), 3))
    val boundExtension = 5::bump
    val unboundExtension = Int::bump
    println(boundExtension.invoke(2))
    println(unboundExtension.invoke(5, 3))
    val constructor = ::Counter
    println(constructor.invoke(8).add(2))
    val noArgs = ::zero
    println(noArgs.invoke())
    val generic: (String) -> String = ::identity
    println(generic.invoke("generic"))
    val higherOrder = ::apply
    println(higherOrder.invoke { 14 })
    val contextual = ::applyOne
    println(contextual.invoke { it + 1 })
    val byte = ::asByte
    println(byte.invoke(127))
    val present: ((Int, Int) -> Int)? = ::add
    val absent: ((Int, Int) -> Int)? = null
    println(present?.invoke(3, 4))
    println(absent?.invoke(3, 4))
    val inferredPresent = nullableReference(true)
    val inferredAbsent = nullableReference(false)
    println(inferredPresent?.invoke(3, 4))
    println(inferredAbsent?.invoke(3, 4))
    val receiver: Int.(Int) -> Int = { delta -> this + delta }
    println(receiver.invoke(4, 5))
    println(Operator().invoke(1))
    val imported = inferredReference()
    println(imported.invoke(4, 5))
    println(imported.name)
    println(imported.call(4, 5))
    val returnedHigher = inferredHigherOrderReference()
    println(returnedHigher.invoke { it + 2 })
    println(returnedHigher.name)
    val forwarded = forwardReference()
    println(forwarded.invoke { it + 2 })
    val boundHigher = Counter(10)::applyMapped
    println(boundHigher.invoke { it + 3 })
    val explicitlyInline = ::explicitInline
    println(explicitlyInline.invoke { it + 1 })
    val receiverReference: Int.(() -> Int) -> Int = ::applyAt
    println(receiverReference.invoke(10) { 2 })
    val thrown = IllegalStateException("callback")
    val throwing = ::apply
    try {
        throwing.invoke { throw thrown }
        println("missed exception")
    } catch (e: IllegalStateException) {
        println(e === thrown)
    }
}
