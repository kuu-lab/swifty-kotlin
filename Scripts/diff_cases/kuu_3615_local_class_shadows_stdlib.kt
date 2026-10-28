// KUU-3615: a file-local declaration must shadow the bundled kotlin.*
// default-imported type of the same name in every position — return type,
// parameter type, receiver type, local annotation, and call expression —
// so all unqualified references resolve to the local declaration.

@JvmInline
value class UInt(val data: Int) {
    fun result() = "OK"
}

class ULong(val data: Long) {
    fun result() = "UL"
}

class UIntArray(val size: Int) {
    fun describe() = "ARR"
    fun total() = size + size
}

class IntArray(val size: Int) {
    fun result() = "IA"
}

fun g(): UInt = UInt(5)
fun h(u: UInt) = u.result()
fun takesArray(a: UIntArray) = a.describe()
fun makesULong(x: ULong): ULong = x

fun main() {
    val u: UInt = UInt(1)
    println(u.result())
    println(g().result())
    println(h(UInt(2)))

    val ua: UIntArray = UIntArray(3)
    println(ua.describe())
    println(takesArray(UIntArray(4)))
    println(UIntArray(1).size)
    println(UIntArray(2).total())

    val ia: IntArray = IntArray(9)
    println(ia.result())
    println(IntArray(8).size)

    val ul: ULong = makesULong(ULong(9))
    println(ul.result())
    println(makesULong(ULong(7)).data)
}
