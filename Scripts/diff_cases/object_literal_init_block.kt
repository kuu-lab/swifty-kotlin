// `init {}` blocks inside an object expression run at construction, interleaved
// with property initializers in declaration order.
interface G { fun greet(): String }

abstract class Base(val tag: String) {
    init { println("Base init $tag") }
    abstract fun describe(): String
}

fun makeBase(prefix: String): Base {
    var counter = 0
    return object : Base("b") {
        val first = "$prefix-first".also { println("first initializer") }
        init {
            counter += 1
            println("init 1: $first counter=$counter")
        }
        val second = first.length
        init { println("init 2: second=$second") }
        override fun describe() = "$tag/$first/$second/$counter"
    }
}

fun main() {
    val g = object : G {
        init { println("init") }
        override fun greet() = "hi"
    }
    println(g.greet())

    val b = makeBase("p")
    println(b.describe())

    val one = object { init { println("single-line init") }; val v = 1 }
    println(one.v)
}
