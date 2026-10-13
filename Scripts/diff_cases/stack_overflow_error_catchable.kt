// KUU-1384: deep recursion must surface a catchable StackOverflowError
// instead of crashing the process with SIGSEGV, and the type itself must
// resolve for typed catch clauses.

fun factNoTail(n: Int): Long = if (n <= 1) 1 else n * factNoTail(n - 1)

fun main() {
    println(try { factNoTail(200000) } catch (e: Throwable) { "caught" })
    println("after")

    println(try { throw StackOverflowError("x") } catch (e: StackOverflowError) { "soe:${e.message}" })

    // StackOverflowError extends Error, not Exception.
    println(try { throw StackOverflowError() } catch (e: Exception) { "wrong" } catch (e: Error) { "error" })
}
