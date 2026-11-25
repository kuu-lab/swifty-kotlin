// Regression: firstNotNullOf/OrNull transform must keep null-skipping when the
// enclosing expected result type is Unit. Seeding the lambda's expected return
// as non-null Unit would coerce the body's `null` to Unit and stop at the
// first element; kotlinc keeps scanning to the first non-null transform result.
fun main() {
    val list = listOf(1, 2, 3)

    var count = 0
    val x: Unit = list.firstNotNullOf {
        count++
        if (it == 2) Unit else null
    }
    println("firstNotNullOf count=$count")
    println("x=$x")

    var count2 = 0
    val y: Unit? = list.firstNotNullOfOrNull {
        count2++
        if (it == 2) Unit else null
    }
    println("firstNotNullOfOrNull count=$count2")
    println("y=$y")
}
