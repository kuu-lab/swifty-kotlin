// KUU-1384: deep recursion must surface a catchable StackOverflowError
// instead of crashing the process with SIGSEGV, and the type itself must
// resolve for typed catch clauses.
//
// KUU-3721: the depth must outgrow the native stack even at the smallest
// optimized frame. Optimized factNoTail frames measure ~48 bytes on
// arm64/x86-64; at 200000 calls (~9.6MB) the recursion fit inside a 16MB
// runner stack at -O2 and printed the wrapped factorial (0) instead of
// throwing. 20000000 frames need >= ~640MB at a conservative 32B frame
// floor, beyond any supported default stack, so every opt level must
// overflow while the JVM reference still throws StackOverflowError first.

fun factNoTail(n: Int): Long = if (n <= 1) 1 else n * factNoTail(n - 1)

fun main() {
    println(try { factNoTail(20000000) } catch (e: Throwable) { "caught" })
    println("after")

    println(try { throw StackOverflowError("x") } catch (e: StackOverflowError) { "soe:${e.message}" })

    // StackOverflowError extends Error, not Exception.
    println(try { throw StackOverflowError() } catch (e: Exception) { "wrong" } catch (e: Error) { "error" })
}
