// KUU-1971: lexical classifiers in ordinary blocks and do-while conditions.
fun main() {
    if (true) {
        class S { val left = 30 }
        println(S().left)
    }
    if (true) {
        class S { val right = 40 }
        println(S().right)
    }
    try {
        class S { val value = 50 }
        println(S().value)
    } finally {
        class S { fun value() = 60 }
        println(S().value())
    }
    do {
        class S { val loop = 90; fun again() = false }
        println(S().loop)
    } while (S().again())
    do {
        class S { val nextLoop = 100; fun again() = false }
        println(S().nextLoop)
    } while (S().again())
}
