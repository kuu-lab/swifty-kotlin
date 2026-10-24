// KUU-3076: bound member property references on a local receiver used to
// SIGBUS at runtime — `s::length.get()` called an invalid pointer.
class C(val x: Int) {
    val doubled: Int
        get() = x * 2
    var name: String = "unset"
}

fun main() {
    val s: String = "x"
    println(s::length.get())
    println((s::length)())
    println(s::length.name)

    val c = C(21)
    println(c::doubled.get())
    println((c::doubled)())

    val mutable = c::name
    println(mutable.get())
    mutable.set("renamed")
    println(mutable.get())
    println(c.name)

    val throughVal = s::length
    println(throughVal.get())
    println(throughVal())
}
