// `ArrayList<E>` is a typealias for `MutableList<E>` (CollectionAliases.kt) — the
// runtime represents every mutable collection with a single boxed implementation
// per kind rather than a real java.util.ArrayList class. Subclassing it via
// constructor-call syntax therefore does not attach any backing storage to the
// derived instance: verified experimentally that `add`/`size`/`get`/`contains`
// on such an instance silently operate on nothing (size stays 0, indexed reads
// return null, contains is always false) rather than throwing.
//
// KSP-933 (TODO.md) tracks giving `ArrayList` a real source-backed class
// declaration (`AbstractMutableList`/`MutableList`/`RandomAccess`, matching the
// JVM stdlib) the way `LinkedHashSet` already got for `MutableSet`
// (CollectionAliases.kt). Until then, these errors are the correct, intentional
// rejection of this unsupported pattern — see arraylist_alias.kt for the
// supported usages (typed variables, bare `ArrayList()` construction, extension
// functions, generic bounds).
class MyList : ArrayList<String>() {
    fun customOp() = "custom"
}
