// KUU-1029: unqualified private companion helpers are visible to their owner.
class M {
    fun put(k: String): Int = helper(k)

    private companion object {
        private fun helper(s: String): Int = s.length
    }
}

class Named {
    fun put(k: String): Int = helper(k)

    private companion object Factory {
        private fun helper(s: String): Int = s.length
    }
}

fun main() {
    println(M().put("hello"))
    println(Named().put("Kotlin"))
}
