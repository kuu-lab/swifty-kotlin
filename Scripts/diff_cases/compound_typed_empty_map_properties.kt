class ScopeHolder {
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    fun beginScope() { scopes += mutableMapOf() }
}

val globalScopes = ArrayDeque<MutableMap<String, Boolean>>()

fun main() {
    val holder = ScopeHolder()
    holder.beginScope()
    holder.scopes += mutableMapOf()
    globalScopes += mutableMapOf()
    println(holder.scopes.size)
    println(globalScopes.size)

    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    scopes += mutableMapOf<String, Boolean>()
    scopes.add(mutableMapOf())
    println(scopes.size)
}
