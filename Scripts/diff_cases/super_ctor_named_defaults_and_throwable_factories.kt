// Superclass constructor calls written in a class / object header or as a
// secondary constructor's `super(...)` must honour named arguments and
// defaults, and an Exception subclass must keep the message / cause given to
// a runtime-backed Exception constructor.
open class Base(val x: Int = 7, val y: Int = 8)
class D1 : Base()
class D2 : Base(y = 1, x = 2)
class D3 : Base(y = 5)
object O1 : Base()
object O2 : Base(y = 3, x = 4)

class P(val a: Int, val b: Int = 10) {
    constructor(s: String) : this(s.length)
    constructor(x: Int, s: String) : this(b = x, a = s.length)
}

class Sec : Base {
    constructor() : super(y = 9)
}

class MyEx : Exception {
    constructor(msg: String) : super(msg)
    constructor(msg: String, c: Throwable) : super(msg, c)
}

class CauseOnly(c: Throwable) : Exception(c)
class Both(m: String, c: Throwable) : Exception(m, c)
class CauseOnlySecondary : RuntimeException {
    constructor(c: Throwable) : super(c)
}
object ObjEx : IllegalStateException("from object")

fun main() {
    val a = D1(); println("${a.x} ${a.y}")
    val b = D2(); println("${b.x} ${b.y}")
    val c = D3(); println("${c.x} ${c.y}")
    println("${O1.x} ${O1.y}")
    println("${O2.x} ${O2.y}")
    val p = P("abc"); println("${p.a} ${p.b}")
    val q = P(5, "hi"); println("${q.a} ${q.b}")
    val s = Sec(); println("${s.x} ${s.y}")

    try { throw MyEx("boom") } catch (e: Exception) { println(e.message) }
    val root = IllegalStateException("root")
    val two = MyEx("outer", root)
    println("${two.message} ${two.cause?.message}")
    val co = CauseOnly(root)
    println("${co.cause?.message} ${co.cause === root} ${co.message?.endsWith("root")}")
    val nb = Both("m", root)
    println("${nb.message} ${nb.cause?.message}")
    val cs = CauseOnlySecondary(root)
    println("${cs.cause?.message} ${cs.message?.endsWith("root")}")
    println(RuntimeException(root).message?.endsWith("root"))
    println(ObjEx.message)
    println(CauseOnly(IllegalArgumentException()).message?.endsWith("IllegalArgumentException"))
}
