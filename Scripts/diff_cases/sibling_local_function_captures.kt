fun oneCapture(a: Double): Double {
    fun within(x: Double, y: Double): Double = x + y + a
    var x = 1.0
    var y = 2.0
    fun rxy(): Double = within(x, y)
    return rxy()
}

fun twoCaptures(a: Double, b: Double): Double {
    fun within(x: Double, y: Double): Double = x + y + a + b
    var x = 1.0
    var y = 2.0
    fun rxy(): Double = within(x, y)
    return rxy()
}

fun directCall(a: Double, b: Double): Double {
    fun within(x: Double, y: Double): Double = x + y + a + b
    return within(1.0, 2.0)
}

fun noCapture(): Double {
    fun within(x: Double, y: Double): Double = x + y
    var x = 1.0
    var y = 2.0
    fun rxy(): Double = within(x, y)
    return rxy()
}

fun main() {
    println(oneCapture(10.0))
    println(twoCaptures(10.0, 20.0))
    println(directCall(10.0, 20.0))
    println(noCapture())
}
