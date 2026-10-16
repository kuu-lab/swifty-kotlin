package math

import java.lang.IllegalArgumentException
import kotlin.math.PI as KotlinPI
import kotlin.math.pow

fun areaOfACircle(radius: Double) =
    if (radius > 0) Math.PI * radius.pow(2.0)
    else throw IllegalArgumentException("Radius must be positive")

fun main() {
    println(Math.PI)
    println(KotlinPI)
    println(areaOfACircle(2.0))
    println(Math.PI.toRawBits() == 0x400921fb54442d18L)
}
