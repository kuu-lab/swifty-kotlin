import kotlin.random.Random

fun main() {
    // nextFloat() - returns value in [0, 1)
    var ok1 = true
    repeat(100) {
        val x = Random.nextFloat()
        if (x < 0.0f || x >= 1.0f) {
            ok1 = false
        }
    }
    println("nextFloat() in range: $ok1")

    // nextFloat(until) - returns value in [0, until)
    var ok2 = true
    repeat(100) {
        val x = Random.nextFloat(5.0f)
        if (x < 0.0f || x >= 5.0f) {
            ok2 = false
        }
    }
    println("nextFloat(5.0f) in range: $ok2")

    println("OK")
}
