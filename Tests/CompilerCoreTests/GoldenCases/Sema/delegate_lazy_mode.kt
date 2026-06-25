package golden.sema

// MIGRATION-PROP-002: lazy with explicit LazyThreadSafetyMode.
//
// Tests that LazyThreadSafetyMode is recognized as a sema type and that
// the 2-arg lazy(mode) { ... } overload resolves correctly.

val syncProp: String by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
    "synchronized"
}

val pubProp: String by lazy(LazyThreadSafetyMode.PUBLICATION) {
    "publication"
}

val noneProp: String by lazy(LazyThreadSafetyMode.NONE) {
    "none"
}

fun main() {
    println(syncProp)
    println(pubProp)
    println(noneProp)
}
