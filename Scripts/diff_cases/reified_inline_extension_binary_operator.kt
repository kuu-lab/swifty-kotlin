operator inline fun <reified T : Number> T.plus(other: T): T = this
operator inline fun <reified T : Number> T.minus(other: T): T = this
operator inline fun <T : Number> T.times(other: T): T = this

inline fun <reified T : Number> duplicatePlus(left: T, right: T): T = left + right
inline fun <reified T : Number> duplicateMinus(left: T, right: T): T = left - right
inline fun <reified T : Number> explicitPlus(left: T, right: T): T = left.plus(right)
inline fun <reified T : Number> nonReifiedOperatorControl(left: T, right: T): T = left * right

fun main() {
    println(duplicatePlus(1, 2))
    println(duplicatePlus(1L, 2L))
    println(duplicateMinus(3, 1))
    println(duplicateMinus(3L, 1L))
    println(explicitPlus(1, 2))
    println(explicitPlus(1L, 2L))
    println(nonReifiedOperatorControl(2, 3))
    println(nonReifiedOperatorControl(2L, 3L))
}
