// BUG-607: interface-typed receivers must use the same itable method slots
// regardless of whether a property is declared before a function or after it.
// A default method must not shift the abstract function's slot either.

interface P1 { val name: String; fun area(): Double }

class R1 : P1 {
    override val name get() = "first"
    override fun area() = 6.0
}

interface P2 { fun area(): Double; val name: String }

class R2 : P2 {
    override fun area() = 7.0
    override val name get() = "second"
}

interface P3 { val name: String; fun area(): Double }

class R3 : P3 {
    override val name get() = "third"
    override fun area() = 8.0
}

interface P4 { fun area(): Double }

class R4 : P4 {
    override fun area() = 9.0
}

interface P5 { val name: String; fun area(): Double; fun describe(): String = "$name:${area()}" }

class R5 : P5 {
    override val name = "default"
    override fun area() = 5.0
}

fun main() {
    val first: P1 = R1()
    println(first.area())
    println(first.name)

    val second: P2 = R2()
    println(second.area())
    println(second.name)

    val third: P3 = R3()
    println(third.area())
    println(third.name)

    val fourth: P4 = R4()
    println(fourth.area())

    val withDefault: P5 = R5()
    println(withDefault.area())
    println(withDefault.describe())

    val shapes: List<P5> = listOf(R5())
    println(shapes.sumOf { it.area() })
}
