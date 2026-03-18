fun main() {
    // Basic passing calls
    require(true)
    check(true)

    // Verify lazyMessage lambdas are not evaluated when condition is true
    var counter = 0
    require(true) { counter++; "should not fail" }
    check(true) { counter++; "should not fail" }
    println("lazy counter: $counter") // expect 0: lambdas were not called

    // Helper to run a block and print the caught exception message
    fun runAndPrintMessage(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            println(e.message)
        }
    }

    runAndPrintMessage { require(false) { "require failed" } }
    runAndPrintMessage { check(false) { "check failed" } }
    runAndPrintMessage { error("test error") }
}
