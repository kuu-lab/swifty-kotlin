// EXPECT-STDOUT: OK
// KUU-4608: in-place `plusAssign` does not rebind the captured local, so the
// stable member smart cast stays valid for kotlinc and KSwiftK.
class Box(val s: String?)
operator fun Box.plusAssign(i: Int) {}

fun captured(): String {
    var b = Box("ok")
    b += 1
    fun read(): String {
        if (b.s != null) return b.s
        return "FAIL"
    }
    return read()
}

fun flow(): String {
    var b = Box("ok")
    b += 1
    if (b.s != null) {
        val y: String = b.s
        return y
    }
    return "FAIL"
}

fun main() {
    if (captured() != "ok" || flow() != "ok") {
        println("FAIL")
        return
    }
    println("OK")
}
