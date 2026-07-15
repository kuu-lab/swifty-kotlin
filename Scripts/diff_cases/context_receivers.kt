// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
class Context(val prefix: String)

class Greeter {
    context(Context)
    fun run() {
        println(message())
        println(secondary())
    }
}

context(Context)
fun message(): String = prefix + " hello"

context(Context)
fun secondary(): String = prefix.uppercase()

fun main() {
    with(Context("hi")) {
        Greeter().run()
    }
}
