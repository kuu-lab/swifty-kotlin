// KUU-3913: a non-callable member property never occupies the callable
// namespace, so `name()` resolves the same-named outer-tier function
// (ktor-http `allStatusCodes`). A function-typed member stays callable and
// still wins by invoking its value.
class StatusCode {
    companion object {
        val allStatusCodes: List<StatusCode> = allStatusCodes()
    }

    val code: Int = code()

    val f: () -> Int = { 41 }
    fun callableValue(): Int = f()
}
fun allStatusCodes(): List<StatusCode> = listOf(StatusCode())
fun code(): Int = 7
fun f(): Int = 100

fun main() {
    println(StatusCode.allStatusCodes.size)
    println(StatusCode().code)
    println(StatusCode().callableValue())
}
