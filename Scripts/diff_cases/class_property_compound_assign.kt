// Compound assignment (`+=`, `-=`, `*=`, postfix `++`) on a class instance's
// own stored property, referenced via the implicit `this` receiver from
// inside its methods or an `init` block, must update the per-instance field
// (not silently no-op).
class Counter {
    var value: Int = 10
    fun add(n: Int) {
        value += n
    }
    fun sub(n: Int) {
        value -= n
    }
    fun double() {
        value *= 2
    }
    fun bump(): Int {
        value++
        return value
    }
}

class Accumulator(val seed: Int) {
    var total: Int = seed
    init {
        total += seed
    }
    fun addAll(vararg xs: Int): Int {
        for (x in xs) {
            total += x
        }
        return total
    }
}

fun main() {
    val c = Counter()
    c.add(5)
    println(c.value)
    c.sub(2)
    println(c.value)
    c.double()
    println(c.value)
    println(c.bump())

    val a = Accumulator(3)
    println(a.total)
    println(a.addAll(1, 2, 3))
}
