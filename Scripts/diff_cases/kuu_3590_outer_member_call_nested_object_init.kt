// KUU-3590: preserve the enclosing receiver through run and an object initializer.
class C(result: String) {
    var result: String = "Failed"
    init {
        run {
            object {
                init { completed(result) }
            }
        }
    }
    fun completed(value: String) { this.result = value }
}

fun main() { println(C("OK").result) }
