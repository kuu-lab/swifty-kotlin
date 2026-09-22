private fun clientCookies(pairs: List<Pair<String, String>>, skipEscaped: Boolean): List<Pair<String, String>> =
    pairs
        .filter { !skipEscaped || !it.first.startsWith("$") }
        .map { cookie ->
            if (cookie.second.startsWith("\"") && cookie.second.endsWith("\"")) {
                cookie.copy(second = cookie.second.removeSurrounding("\""))
            } else {
                cookie
            }
        }

fun main() {
    println(clientCookies(listOf("a" to "b", "c" to "\"d\""), false))
}
