// KUU-4420: binary operator syntax must resolve member-extension operators
// declared on an implicit dispatch receiver (`with(ring) { a + b }`), for
// both concrete and generic extension receivers.
interface Ring<T> {
    operator fun T.plus(arg: T): T
    operator fun T.times(arg: T): T
    operator fun T.minus(arg: T): T
}

class V(val x: Int)

class VRing : Ring<V> {
    override operator fun V.plus(arg: V): V = V(this.x + arg.x)
    override operator fun V.times(arg: V): V = V(this.x * arg.x)
    override operator fun V.minus(arg: V): V = V(this.x - arg.x)
}

class IntRing : Ring<Int> {
    override operator fun Int.plus(arg: Int): Int = this + arg
    override operator fun Int.times(arg: Int): Int = this * arg
    override operator fun Int.minus(arg: Int): Int = this - arg
}

fun <T> withPlus(ring: Ring<T>, a: T, b: T): T = with(ring) { a + b }
fun <T> withTimes(ring: Ring<T>, a: T, b: T): T = with(ring) { a * b }
fun <T> withMinus(ring: Ring<T>, a: T, b: T): T = with(ring) { a - b }

fun <T> Ring<T>.memberCombine(a: T, b: T): T = a + b
fun <T> Ring<T>.accumulate(a: T, b: T): T {
    var sum = a
    sum += b
    return sum
}

class Counter(var v: Int)

class CounterAcc {
    operator fun Counter.plusAssign(d: Int) { v += d }
}

fun main() {
    val vring = VRing()
    println(withPlus(vring, V(20), V(22)).x)
    println(withTimes(vring, V(6), V(7)).x)
    println(withMinus(vring, V(50), V(8)).x)
    println(vring.memberCombine(V(19), V(23)).x)
    println(vring.accumulate(V(30), V(12)).x)

    val ring = IntRing()
    println(withPlus(ring, 20, 22))
    println(ring.memberCombine(19, 23))

    val counter = Counter(10)
    with(CounterAcc()) { counter += 5 }
    println(counter.v)
}
