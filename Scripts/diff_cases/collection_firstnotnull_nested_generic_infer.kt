// firstNotNullOf/OrNull transform lambda must infer a nested return-only
// generic call's type argument from the enclosing expected type — the
// koin-core CoreResolver.resolveFromContextOrNull shape. kotlinc accepts it.
class Scope(val id: String = "") {
    val linkedScopes = ArrayList<Scope>()
}

fun <T> resolveFromContextOrNull(scope: Scope, lookupParent: Boolean = true): T? = null
fun flatten(scopes: List<Scope>): Set<Scope> = scopes.toSet()

fun <T> findOrNull(scope: Scope): T? {
    val hasSingleLink = scope.linkedScopes.size == 1
    val parentScopes = if (!hasSingleLink && scope.linkedScopes.size > 1) flatten(scope.linkedScopes) else scope.linkedScopes
    return parentScopes.firstNotNullOfOrNull {
        resolveFromContextOrNull(it, lookupParent = hasSingleLink)
    }
}

fun findConcrete(scope: Scope): String? {
    return scope.linkedScopes.firstNotNullOfOrNull {
        resolveFromContextOrNull(it, lookupParent = true)
    }
}

fun main() {
    val root = Scope("root")
    val child = Scope("child")
    root.linkedScopes.add(child)
    child.linkedScopes.add(Scope("leaf"))
    val inferred: String? = findOrNull(root)
    println(inferred)
    println(findConcrete(root))
}
