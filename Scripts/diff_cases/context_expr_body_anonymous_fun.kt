// Regression: expression-bodied contextual anonymous functions used to be
// rejected with "Expected '{' for anonymous function body." (KUU-3170).
fun main() {
    with("O") {
        val f = context(a: String) fun(y: String): String = a + y
        println(f("K"))
    }
}
