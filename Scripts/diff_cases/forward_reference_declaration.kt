fun make(seed: Long): Box = Box(seed.toInt())

fun describe(shape: Shape): String = shape.name()

val defaultBox: Box = Box(7)

fun alias(value: Meters): Meters = value + 1

class Box(val value: Int)

interface Shape {
    fun name(): String
}

object Circle : Shape {
    override fun name(): String = "circle"
}

typealias Meters = Int

class Holder {
    fun wrap(value: Int): Payload = Payload(value)
}

class Payload(val value: Int)

fun main() {
    println(make(3L).value)
    println(defaultBox.value)
    println(describe(Circle))
    println(alias(41))
    println(Holder().wrap(9).value)
}
