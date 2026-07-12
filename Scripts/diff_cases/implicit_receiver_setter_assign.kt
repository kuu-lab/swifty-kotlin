class Foo {
    var x: Int = 1
        set(value) { field = value * 2 }
    fun setAndGet(v: Int): Int {
        x = v
        return x
    }
}

class Box {
    var v: Int = 0
        get() = field + 1000
        set(value) { field = value * 3 }
    fun run(n: Int): Int {
        v = n
        return v
    }
}

fun main() {
    println(Foo().setAndGet(5))
    println(Box().run(4))
}
