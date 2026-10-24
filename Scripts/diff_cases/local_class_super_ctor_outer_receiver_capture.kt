// KUU-3226 (JetBrains kt4174): a local class's superclass constructor
// arguments run inside its generated `<init>`, so references there must go
// through capture fields — including the enclosing `this` when the argument
// names an outer-class member.
open class C(val s: String) {
    fun test(): String = s
}

class B(var x: String) {
    fun foo(): String {
        var s = "OK"
        class Z : C(s) {}
        return Z().test()
    }

    fun foo2(): String {
        class Y : C(x) {}
        return Y().test()
    }
}

class B2(val x: String, var y: String) {
    fun describe(): String = x + y

    fun foo2(): String {
        class Y1 : C(x) {}
        class Y2 : C(y) {}
        class Y3 : C(describe()) {}
        class Y4 : C(this@B2.x) {}
        return Y1().test() + "|" + Y2().test() + "|" + Y3().test() + "|" + Y4().test()
    }
}

fun main() {
    println(B("OK").foo())
    println(B("OK").foo2())
    val b2 = B2("A", "B")
    println(b2.foo2())
    b2.y = "B2"
    println(b2.foo2())
}
