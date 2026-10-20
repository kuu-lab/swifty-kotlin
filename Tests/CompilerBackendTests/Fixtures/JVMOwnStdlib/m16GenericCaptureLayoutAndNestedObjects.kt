fun main() {
    val a = box(1); val b = box("text"); println(a.get()); println(b.get())
    val x = mutableBox(2); val y = mutableBox("before")
    x.set(7); y.set("after"); println(x.get()); println(y.get()); println(x.matches(7)); println(y.matches(null))
    val p = nested<Int, String?>(); println(p.first(1)); println(p.second(null)); println(p.first("wrong"))
    val inner = Outer(4).Inner()
    val f: (Int) -> Int = inner::add; println(f(3))
    println(memberReference<Int, String>()("wrong")); println(memberReference<String, String>()("yes")); println(memberReference<String?, String?>()(null))
}
interface Box<T> { fun get(): T }
inline fun <reified T> box(value: T): Box<T> = object: Box<T> { override fun get(): T = value }
interface Mutable<T> { fun get(): T; fun set(value: T); fun matches(v: Any?): Boolean }
inline fun <reified T> mutableBox(value: T): Mutable<T> {
    var current = value
    return object: Mutable<T> {
        override fun get(): T = current
        override fun set(value: T) { current = value }
        override fun matches(v: Any?): Boolean = v is T
    }
}
interface Dual { fun first(v: Any?): Boolean; fun second(v: Any?): Boolean }
inline fun <reified A, reified B> nested(): Dual {
    val outer = object: Dual {
        override fun first(v: Any?): Boolean = v is A
        override fun second(v: Any?): Boolean {
            val inner = object { fun test(): Boolean = v is B }
            return inner.test()
        }
    }
    return outer
}
inline fun <reified A, reified B> memberReference(): (B) -> Boolean {
    val target = object { inline fun <reified C> matches(v: C): Boolean = v is A }
    return target::matches
}
class Outer(val value: Int) {
    inner class Inner { inline fun <reified T> add(n: T): Int = if (n is Int) value + n else 0 }
}
