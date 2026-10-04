// KUU-946: a same-named member only shadows extension functions while some
// member is applicable to the call. Members with a different signature, and
// members the caller cannot access, must not hide the extensions.
interface S {
    fun write(source: ByteArray, startIndex: Int, endIndex: Int)
}
class B : S {
    override fun write(source: ByteArray, startIndex: Int, endIndex: Int) {
        println("member")
    }
}
fun S.write(source: ByteArray) {
    println("extension")
    write(source, 0, source.size)
}

class C {
    fun f(x: String) { println("member-string") }
    private fun g() {}
}
fun C.f(x: Int) { println("extension-int") }
fun C.g(x: Int) { println("extension-g") }

fun main() {
    val b = B()
    b.write(byteArrayOf(1))
    b.write(byteArrayOf(1), 0, 1)
    val s: S = b
    s.write(byteArrayOf(1))
    val c = C()
    c.f("a")
    c.f(1)
    c.g(2)
}
