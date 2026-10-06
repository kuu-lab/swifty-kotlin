// KUU-1027: discarded when values do not require exhaustive Int/Char subjects.
const val SUCCESS: Int = 1
const val FAILURE: Int = 2

class N {
    var attempts: Int = 0
    fun tryIt(): Int {
        attempts += 1
        return if (attempts == 1) 0 else SUCCESS
    }
}

fun attempt(n: N): Int {
    while (true) {
        when (n.tryIt()) {
            SUCCESS -> return n.attempts
            FAILURE -> return -1
        }
    }
}

fun number(): Int = 2

fun main() {
    println(attempt(N()))
    when (number()) { 2 -> println("call") }
    val query = "a&b"
    for (index in 0 until query.length) {
        when (query[index]) { '&' -> continue }
        println(query[index])
    }
    val values = intArrayOf(0, 1, 2)
    for (index in 0 until values.size) {
        when (values[index]) { 1 -> println("array") }
        println(values[index])
    }
}
