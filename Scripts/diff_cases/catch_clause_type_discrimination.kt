// Regression: a catch clause naming a specific (non-catch-all) exception type
// must only match that type or its real supertypes — an earlier, unrelated
// sibling catch clause must never win just because it appears first.
fun main() {
    try {
        val any: Any = 42
        val s = any as String
        println(s)
    } catch (e: IllegalStateException) {
        println("wrong: IllegalStateException")
    } catch (e: ClassCastException) {
        println("right: ClassCastException")
    } catch (e: Exception) {
        println("wrong: Exception fallback")
    }

    try {
        val any: Any = 42
        val s = any as String
        println(s)
    } catch (e: ArithmeticException) {
        println("wrong: ArithmeticException")
    } catch (e: IllegalArgumentException) {
        println("wrong: IllegalArgumentException")
    } catch (e: Exception) {
        println("right: Exception fallback")
    }

    try {
        val zero = 0
        println(1 / zero)
    } catch (e: ClassCastException) {
        println("wrong: ClassCastException")
    } catch (e: ArithmeticException) {
        println("right: ArithmeticException")
    }

    try {
        error("boom")
    } catch (e: ClassCastException) {
        println("wrong: ClassCastException")
    } catch (e: ArithmeticException) {
        println("wrong: ArithmeticException")
    } catch (e: IllegalStateException) {
        println("right: IllegalStateException")
    }
}
