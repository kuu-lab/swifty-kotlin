fun main() {
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    scopes += mutableMapOf()
    println(scopes.size)
}
