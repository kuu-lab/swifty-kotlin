// `ArrayList<E>` is a source-backed `final` class (CollectionAliases.kt,
// KSP-933) implementing `MutableList<E>`/`RandomAccess`/`AbstractMutableList<E>`.
// Being `final`, it rejects subclassing via constructor-call syntax with a
// compile-time diagnostic rather than allowing an instance with no attached
// backing storage — see arraylist_alias.kt for the supported usages (typed
// variables, bare `ArrayList()` construction, extension functions, generic
// bounds).
class MyList : ArrayList<String>() {
    fun customOp() = "custom"
}
