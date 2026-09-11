// `ArrayList<E>` is a source-backed `final` class implementing `MutableList<E>`
// (Sources/CompilerCore/Stdlib/kotlin/collections/CollectionAliases.kt, KSP-933).
// This case verifies parameter / return / property types, nested type
// arguments, upper bounds, extension receivers, and ArrayList / MutableList /
// List compatibility (ArrayList satisfies MutableList and List, not the
// reverse — it is a concrete class, not an alias). Element mutation, indexed
// access and printing are executed by Scripts/diff_cases/arraylist_alias.kt
// and ksp627_collection_aliases.kt.

fun processList(list: ArrayList<String>) {}

fun createList(): ArrayList<Int> {
    return ArrayList<Int>()
}

class Container {
    val items: ArrayList<String> = ArrayList()
    val numbers: ArrayList<Int> = ArrayList<Int>()
}

fun <T : ArrayList<String>> constrain(list: T): T {
    return list
}

fun ArrayList<String>.customExtension(): String {
    return "extended"
}

fun main() {
    // Constructor inference from explicit type arguments alone, checked by the
    // assignments and call below rather than an expected type.
    val explicit = ArrayList<String>()
    val explicitAsMutable: MutableList<String> = explicit
    processList(explicit)

    // Expected-type inference for ArrayList's own type and through MutableList.
    val fromAlias: ArrayList<Double> = ArrayList()
    val fromMutable: MutableList<Boolean> = ArrayList()

    // List (read-only) compatibility.
    val asReadOnly: List<String> = ArrayList()

    // Return type propagation.
    val created = createList()
    val createdAsMutable: MutableList<Int> = created

    // Property type propagation.
    val holder = Container()
    val items: MutableList<String> = holder.items
    val numbers: ArrayList<Int> = holder.numbers

    // Nested type arguments (generics are invariant, so the outer ArrayList ->
    // MutableList upcast requires the inner type argument to match exactly).
    val nested: ArrayList<ArrayList<String>> = ArrayList()
    val nestedAsMutable: MutableList<ArrayList<String>> = nested

    // Upper-bound constraint and return propagation.
    val constrained = constrain(explicit)
    val constrainedAsMutable: MutableList<String> = constrained

    // Extension receiver on ArrayList.
    val extended: String = explicit.customExtension()
}
