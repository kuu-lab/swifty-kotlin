class Outer(val x: Int) {
    var counter = 0

    inner class Inner(val y: Int) {
        fun greet() = "inner ${x + y}"
        fun xOnly() = "x=$x"
        fun yOnly() = "y=$y"
        fun qualifiedX() = "qx=${this@Outer.x}"

        fun bump() {
            counter++
            this@Outer.counter += 10
        }

        inner class Deep {
            fun all() = "deep ${x}/${y}/${this@Outer.counter}"
        }

        fun deepInstance() = Deep()
    }

    fun makeInner(value: Int) = Inner(value)
}

fun main() {
    val outer = Outer(1)
    val inner = outer.Inner(2)
    println(inner.greet())
    println(inner.xOnly())
    println(inner.yOnly())
    println(inner.qualifiedX())

    val g = inner::greet
    println(g())
    println((Outer(10).Inner(20)::greet)())

    inner.bump()
    println(outer.counter)

    val deep = inner.deepInstance()
    println(deep.all())

    val innerFromOuter = outer.makeInner(3)
    println(innerFromOuter.greet())
}
