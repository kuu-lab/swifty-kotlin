class Foo(val v: Int)

var Foo.tag: String
    get() = "tag$v"
    set(value) {
        println("set tag $value")
    }

var counter = 0

var Int.bumped: Int
    get() = this + counter
    set(value) {
        counter = value - this
    }

fun main() {
    val f = Foo(5)
    println(f.tag)
    f.tag = "zz"
    5.bumped = 8
    println(counter)
    println(2.bumped)
}
