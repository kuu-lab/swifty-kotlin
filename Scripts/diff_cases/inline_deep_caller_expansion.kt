inline fun stage01(value: Int, block: (Int) -> Int): Int = stage02(value + 1, block)
inline fun stage02(value: Int, block: (Int) -> Int): Int = stage03(value + 1, block)
inline fun stage03(value: Int, block: (Int) -> Int): Int = stage04(value + 1, block)
inline fun stage04(value: Int, block: (Int) -> Int): Int = stage05(value + 1, block)
inline fun stage05(value: Int, block: (Int) -> Int): Int = stage06(value + 1, block)
inline fun stage06(value: Int, block: (Int) -> Int): Int = stage07(value + 1, block)
inline fun stage07(value: Int, block: (Int) -> Int): Int = stage08(value + 1, block)
inline fun stage08(value: Int, block: (Int) -> Int): Int = stage09(value + 1, block)
inline fun stage09(value: Int, block: (Int) -> Int): Int = stage10(value + 1, block)
inline fun stage10(value: Int, block: (Int) -> Int): Int = stage11(value + 1, block)
inline fun stage11(value: Int, block: (Int) -> Int): Int = stage12(value + 1, block)
inline fun stage12(value: Int, block: (Int) -> Int): Int = block(value + 1)

fun escape(): Int {
    stage01(0) { return it + 100 }
    return -1
}

inline fun once(block: () -> Unit) { block() }

fun nestedEscape(): Int {
    once { once { return 42 } }
    return 0
}

fun main() {
    println(stage01(0) { it * 2 })
    println(stage01(5) { stage01(it) { nested -> nested + 1 } })
    println(escape())
    println(nestedEscape())
    try {
        stage01(0) { throw IllegalStateException("deep-inline") }
    } catch (error: IllegalStateException) {
        println(error.message)
    } finally {
        println("finally")
    }
}
