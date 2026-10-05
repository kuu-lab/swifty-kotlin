class Outer {
    class Nested(val v: Int)
}

class Outer3 {
    class Nested(var v: Int)
}

class Outer2 {
    class Nested {
        val v: Int = 6
    }
}

class HasInner(val x: Int) {
    inner class Inner(val y: Int) {
        fun sum(): Int = x + y
    }
}

sealed class Shape {
    class Cir(val r: Int) : Shape()
    class Rect(var w: Int, val h: Int) : Shape()
}

fun describe(shape: Shape): String = when (shape) {
    is Shape.Cir -> "circle=${shape.r}"
    is Shape.Rect -> "rect=${shape.w * shape.h}"
}

fun main() {
    println("a")
    val n = Outer.Nested(1)
    println("b ${n.v}")

    val mutable = Outer3.Nested(2)
    println(mutable.v)
    mutable.v = 3
    println(mutable.v)
    val other = Outer3.Nested(9)
    println(other.v)
    println(mutable.v)

    println(Outer2.Nested().v)
    println(HasInner(4).Inner(5).sum())
    println(describe(Shape.Cir(5)))
    val rect = Shape.Rect(2, 7)
    rect.w = 3
    println(describe(rect))
}
