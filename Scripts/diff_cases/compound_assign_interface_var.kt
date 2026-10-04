interface Holder<T> {
    var value: T
}

class IntHolder(override var value: Int) : Holder<Int>

interface IntBox {
    var n: Int
}

class IB(override var n: Int) : IntBox

fun main() {
    val h1 = IntHolder(1)
    val hh: Holder<Int> = h1
    hh.value = 5
    println(h1.value)
    hh.value += 10
    println(h1.value)
    val b: IntBox = IB(1)
    b.n += 2
    b.n++
    println(b.n)
}
