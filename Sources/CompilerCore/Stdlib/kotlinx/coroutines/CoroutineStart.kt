package kotlinx.coroutines

// Declared in Kotlin source (KUU-4375) so the enum value surface —
// `name`, `ordinal`, `values()`, `toString()` — behaves like the JVM
// enum instead of the collapsed synthetic markers. The launch/async
// start-mode rewrite only reads the entry's fqName, which stays
// `kotlinx.coroutines.CoroutineStart.<ENTRY>` either way. `isLazy`
// remains the synthetic compile-time-folded property registered by the
// coroutine header helpers.
public enum class CoroutineStart {
    DEFAULT,
    LAZY,
    ATOMIC,
    UNDISPATCHED,
}
