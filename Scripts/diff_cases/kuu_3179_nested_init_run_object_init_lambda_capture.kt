// KUU-3179: inline object init blocks must forward captures through enclosing lambdas.
fun doSomething(action: () -> Unit) {
    action()
}

class CompilerBug1(result: String) {
    var result = "Failed"
    init {
        run { object { init { doSomething { completed(result) } } } }
    }
    fun completed(value: String) { this.result = value }
}

fun main() {
    println(CompilerBug1("OK").result)
}
