class VarArgs(val x: String?)
class VarInner(val x: Any?)
class VarOuter(val inner: VarInner?)

fun nullCheck(value: String?) {
    var args = VarArgs(value)
    if (args.x != null) println(args.x.length) else println("null")
    if (args.x != null && args.x.length > 0) println(args.x.length)
    when (args.x) {
        null -> println("missing")
        else -> println(args.x.length)
    }
}

fun guardReturn(value: String?) {
    var args = VarArgs(value)
    if (args.x == null) return
    println(args.x.length)
}

fun main() {
    nullCheck("hello")
    nullCheck(null)
    guardReturn("guard")
    guardReturn(null)
    var args = VarArgs("contract")
    requireNotNull(args.x)
    println(args.x.length)
    var outer = VarOuter(VarInner("nested"))
    if (outer.inner != null && outer.inner.x is String) println(outer.inner.x.length)
    var captured = VarArgs("capture")
    val reader = { if (captured.x != null) println(captured.x.length) }
    reader()
    fun read() { if (captured.x != null) println(captured.x.length) }
    read()
    var loops = VarArgs("loop")
    var i = 0
    while (i < 2) {
        if (loops.x != null) println(loops.x.length)
        i += 1
    }
    if (args.x != null) {
        var args = VarArgs(null)
        args = VarArgs("shadow")
        println(args.x)
    }
    println(args.x.length)
}
