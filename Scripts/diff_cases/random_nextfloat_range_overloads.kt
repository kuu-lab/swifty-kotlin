// SKIP-DIFF (DEBT-DIFF-005): Random.nextFloat(until) / nextFloat(from, until) are KSwiftK synthetic
// extensions (see Stdlib/kotlin/random/Random.kt) not present in kotlin.random.Random's JVM stdlib
// surface (kotlinc rejects them as "too many arguments for 'fun nextFloat(): Float'"), so the JVM
// kotlinc reference cannot compile this case. Split out of random_extended.kt (STDLIB-655).
import kotlin.random.Random

fun main() {
    // STDLIB-655: nextFloat(until)
    var okFloatUntil = true
    repeat(100) {
        val f = Random.nextFloat(5.0f)
        if (f < 0.0f || f >= 5.0f) {
            okFloatUntil = false
        }
    }
    println("nextFloat(5.0f) in range: $okFloatUntil")

    // STDLIB-655: nextFloat(from, until)
    var okFloatRange = true
    repeat(100) {
        val f = Random.nextFloat(1.0f, 10.0f)
        if (f < 1.0f || f >= 10.0f) {
            okFloatRange = false
        }
    }
    println("nextFloat(1.0f, 10.0f) in range: $okFloatRange")

    // Instance-method form split out of random_overload_edge_cases.kt.
    val r = Random(7)
    val floatVal = r.nextFloat(1.0f, 2.0f)
    println(floatVal >= 1.0f && floatVal < 2.0f)

    println("OK")
}
