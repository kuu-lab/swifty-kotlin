// KUU-1023: Kotlin accepts leading-dot Double and Float literals.
fun doubleValue(value: Double): Double = value
fun floatValue(value: Float): Float = value
fun sum(left: Double, right: Float): Double = left + right
fun literalReturn(): Double = .5

fun main() {
    val double = .5
    val float = .5f
    println(double)
    println(float)
    println(.5)
    println(.5f)
    println(.5F)
    println(doubleValue(.25))
    println(floatValue(.25f))
    println(sum(.25, .5f))
    println(sum(right = .5f, left = .25))
    println(doubleValue(doubleValue(.5)))
    println(literalReturn())
    println((.5))
    println(-.5)
    println(+.5f)
    println(.25e2)
    println(.25E-2)
    println(.25e+2f)
    println(.1_25)
    println(.1_25F)
    println(.5 + .25)
    println(.5f * .5f)
    println(.5.toInt())
    println(.5f.toInt())
    println("${.5}:${.5f}")
    println(listOf(.5, .25)[1])
    println(.5 == 0.5)
    println(.5f == 0.5f)
    println(2 in 1..3)
    println(3 in 1..<3)
}
