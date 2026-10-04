// `get() { ... }` / `set(v) { ... }` written on the property's own line.
// Before the fix, the getter header leaked into the type annotation
// (`Int get()`), so the property lost its custom accessors: `c.p++` reported
// "Ambiguous overload resolution" and `c.p += 1` silently skipped the setter.
class C {
    var backing = 0
    var p: Int get() { println("get"); return backing } set(v) { println("set"); backing = v }
    var q: Int set(v) { println("qset"); backing = v * 10 } get() { println("qget"); return backing }
    var s: Int get() { return backing + 1 }
        set(v) { println("sset"); backing = v }
    val t: Int get(): Int { return backing * 2 }
}

fun main() {
    val c = C()
    // A custom getter runs exactly once for an expression-position `++`.
    val old = c.p++; println(old); println(c.backing)
    val pre = ++c.p; println(pre); println(c.backing)
    c.p += 5; println(c.backing)
    c.q = 3; println(c.q)
    c.s = 7; println(c.s)
    println(c.t)
}
