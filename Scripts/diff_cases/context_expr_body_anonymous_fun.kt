// DIFF_JVM
// Regression: expression-bodied contextual anonymous functions used to be
// rejected with "Expected '{' for anonymous function body." (KUU-3170);
// the JVM backend also rejected their contextual local-function lowering (KUU-4642).
fun main() {
    with("O") {
        val f = context(a: String) fun(y: String): String = a + y
        println(f("K"))
    }
    val zeroParameters = context(a: String) fun() = a
    println(zeroParameters("Z"))
    val extension = context(a: String) fun String.() = this + a
    println(extension("P", "Q"))
}
