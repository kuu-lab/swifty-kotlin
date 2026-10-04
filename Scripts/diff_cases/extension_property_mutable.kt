class Box(var x: Int)

var Box.y: Int
    get() = x
    set(v) { x = v * 2 }

fun main() {
    val b = Box(3)
    println(b.y)
    b.y = 10
    println(b.y)
    println(b.x)
}
