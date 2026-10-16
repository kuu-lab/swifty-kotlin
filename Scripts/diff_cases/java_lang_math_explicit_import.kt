package math

import java.lang.Math
import kotlin.math.PI as KotlinPI
import kotlin.math.pow

fun areaOfACircle(radius: Double) = Math.PI * radius.pow(2.0)

fun main() {
    println(Math.PI)
    println(Math.PI == KotlinPI)
    println(areaOfACircle(2.0))
    println(Math.PI.toRawBits() == 0x400921fb54442d18L)
}
