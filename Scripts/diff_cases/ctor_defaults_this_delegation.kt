class Ctor(val a: Int, val b: String = "b$a", val c: Int = a + b.length) {
    constructor(s: String) : this(s.length, s)
    override fun toString() = "Ctor($a,$b,$c)"
}

class Sub(val x: Int, val y: Int = x * 2) {
    constructor() : this(x = 7)
    constructor(y: Int, marker: Boolean) : this(y = y, x = 1)
    override fun toString() = "Sub($x,$y)"
}

open class Base(val p: Int, val q: String = "q$p") {
    override fun toString() = "Base($p,$q)"
}

class Derived : Base(3)

fun main() {
    println(Ctor(1))
    println(Ctor(2, "zz"))
    println(Ctor("abc"))
    println(Ctor(c = 0, a = 5))
    println(Sub())
    println(Sub(9, true))
    println(Derived())
}
