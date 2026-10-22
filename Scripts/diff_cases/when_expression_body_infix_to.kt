// DIFF_JVM
// KUU-1927: keep the when suffix and following declarations in their own bodies.
// KOTLINC_FLAGS: -jvm-target 17
class WhenToDemo1894 {
    private fun choose(flag: Boolean): Pair<Int, Int> = when (flag) {
        true -> 1
        false -> 2
    } to 3
    fun run() = choose(true)
}

fun whenToPairBlock1894(flag: Boolean): Pair<Int, Int> {
    return when (flag) {
        true -> 1
        false -> 2
    } to 3
}

fun whenToPairTopLevel(flag: Boolean): Pair<Int, Int> = when (flag) {
    true -> 1
    false -> 2
} to 3
fun afterFunction() = 4

fun whenBeforeClass(flag: Boolean): Pair<Int, Int> = when (flag) {
    true -> 1
    false -> 2
} to 3
class AfterClass(val marker: Int = 5)

fun whenBeforeProperty(flag: Boolean): Pair<Int, Int> = when (flag) {
    true -> 1
    false -> 2
} to 3
val afterProperty = 6

fun main() {
    println(WhenToDemo1894().run())
    println(whenToPairBlock1894(true))
    println(whenToPairBlock1894(false))
    println(whenToPairTopLevel(true))
    println(whenToPairTopLevel(false))
    println(whenBeforeClass(true))
    println(whenBeforeProperty(false))
    println(afterFunction())
    println(AfterClass().marker)
    println(afterProperty)
}
