// SKIP-DIFF (DEBT-DIFF-005): Random.nextFloat(until)/nextFloat(from, until) are
// kswiftc-only extensions (STDLIB-655) — real kotlinc's kotlin.random.Random only
// declares the no-arg nextFloat(), so the JVM reference always fails to compile
// this file ("too many arguments for 'fun nextFloat(): Float'"). Split out of
// random_extended.kt so that file's standard-API assertions stay diff-checked
// against the JVM kotlinc reference. Also covers the same gap found in
// random_overload_edge_cases.kt (instance-method nextFloat(from, until)).
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

    // random_overload_edge_cases.kt: r.nextFloat(from, until) instance-method form
    val r = Random(7)
    val floatVal = r.nextFloat(1.0f, 2.0f)
    println(floatVal >= 1.0f && floatVal < 2.0f)

    println("OK")
}
