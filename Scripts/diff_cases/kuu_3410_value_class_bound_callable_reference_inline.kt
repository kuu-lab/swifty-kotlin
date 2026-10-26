inline fun foo(init: () -> String): String = init()

@JvmInline
value class IcInt(val i: Int) {
    fun simple(): String = i.toString()
}

@JvmInline
value class IcLong(val l: Long) {
    fun simple(): String = l.toString()
}

@JvmInline
value class IcAny(val a: Any?) {
    fun simple(): String = a?.toString() ?: "null"
}

@JvmInline
value class IcOverIc(val o: IcLong) {
    fun simple(): String = o.toString()
}

fun testUnboxed(i: IcInt, l: IcLong, a: IcAny, o: IcOverIc): String =
    foo(i::simple) + foo(l::simple) + foo(a::simple) + foo(o::simple)

fun testBoxed(i: IcInt?, l: IcLong?, a: IcAny?, o: IcOverIc?): String =
    foo(i!!::simple) + foo(l!!::simple) + foo(a!!::simple) + foo(o!!::simple)

fun testLocalVars(): String {
    val i = IcInt(0)
    val l = IcLong(1L)
    val a = IcAny(2)
    val o = IcOverIc(IcLong(3L))
    return foo(i::simple) + foo(l::simple) + foo(a::simple) + foo(o::simple)
}

val ip = IcInt(1)
val lp = IcLong(2L)
val ap = IcAny(3)
val op = IcOverIc(IcLong(4L))

fun testGlobalProperties(): String =
    foo(ip::simple) + foo(lp::simple) + foo(ap::simple) + foo(op::simple)

fun testCapturedVars(): String =
    IcInt(2).let { foo(it::simple) } +
        IcLong(3L).let { foo(it::simple) } +
        IcAny(4).let { foo(it::simple) } +
        IcOverIc(IcLong(5L)).let { foo(it::simple) }

fun mark(index: Int, actual: String, expected: String) {
    if (actual == expected) println(index) else println("FAIL-$index:$actual")
}

fun main() {
    mark(0, IcAny(5).simple(), "5")
    mark(1, testUnboxed(IcInt(3), IcLong(4L), IcAny(5), IcOverIc(IcLong(6L))), "345IcLong(l=6)")
    mark(2, testBoxed(IcInt(3), IcLong(4L), IcAny(5), IcOverIc(IcLong(6L))), "345IcLong(l=6)")
    mark(3, testLocalVars(), "012IcLong(l=3)")
    mark(4, testGlobalProperties(), "123IcLong(l=4)")
    mark(5, testCapturedVars(), "234IcLong(l=5)")
    println(6)
    println(7)
}
