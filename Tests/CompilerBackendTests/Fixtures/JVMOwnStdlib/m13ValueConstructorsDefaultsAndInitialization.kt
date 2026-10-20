var events = 0
fun mark(n: Int): Int { events = events * 10 + n; return n }
@JvmInline value class V(val value: Int = mark(10)) {
    init { events = events * 10 + 1 }
    constructor(s: String): this(mark(if (s == "abc") 3 else 2)) { events = events * 10 + 2 }
    constructor(b: Boolean, x: Int = mark(20)): this(if (b) x else mark(30)) { events = events * 10 + 3 }
    constructor(l: Long, s: String = "ok"): this(s) { events = events * 10 + 4 }
    constructor(n: Int, b: Boolean): this(if (b) n else 0) { events = events * 10 + 5 }
}
@JvmInline value class Outer(val value: V = V()) {
    constructor(s: String): this(V(s))
}
fun main() {
    println(V()); println(events); events = 0
    println(V("abc")); println(events); events = 0
    println(V(true)); println(events); events = 0
    println(V(false, x = mark(4))); println(events); events = 0
    println(V(1L)); println(events); events = 0
    println(V(8, true)); println(events); events = 0
    println(Outer()); println(events); events = 0
    val v = V(7); val any: Any = v; println(any); println(events)
    println(Outer("test").value.value)
    val ctor: (String) -> V = ::V; println(ctor("abcde"))
}
