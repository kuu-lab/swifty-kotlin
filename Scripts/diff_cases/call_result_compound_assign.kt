fun main() {
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    scopes.add(mutableMapOf())
    scopes.last() += "x" to true
    println(scopes.last()["x"])
}
