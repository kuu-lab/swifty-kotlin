package kotlin

import kotlin.internal.KsSymbolName
import kotlin.reflect.KProperty

/*
 * KSP-491: real Kotlin implementation of `Lazy`/`lazy`/`lazyOf`, replacing the
 * synthetic `HeaderHelpers+SyntheticPropertyDelegateStubs` shells and the
 * `kk_lazy_*` runtime bridge (RuntimeDelegates.swift/RuntimeTypes.swift).
 *
 * `getValue` is declared as an interface member here (not as the extension
 * function real kotlin-stdlib uses) because property-delegate resolution
 * (`DeclTypeChecker.typeCheckDelegate` -> `collectMemberFunctionCandidates`)
 * only walks members/supertypes, not extension functions in scope
 * (tracked separately as a compiler capability gap). It carries a default
 * body (`= value`) so a class implementing `Lazy<T>` directly -- without
 * using `by lazy { ... }` -- does not also have to implement `getValue`
 * itself, matching real kotlin-stdlib's extension-based shape where only
 * `value`/`isInitialized` are abstract.
 */
public interface Lazy<out T> {
    public val value: T
    public fun isInitialized(): Boolean
    public operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
}

@KsSymbolName("__kk_lazy_sync_lock")
internal external fun __lazySyncLock(lock: Any): Unit

@KsSymbolName("__kk_lazy_sync_unlock")
internal external fun __lazySyncUnlock(lock: Any): Unit

// `initializer` is kept non-nullable (rather than nulled out after first use
// to release the closure for GC, as a hand-written impl normally would):
// this compiler doesn't resolve invoking a nullable function-typed value
// through `!!`/`?.invoke()` (a compiler capability gap unrelated to KSP-491).
// `lazyOf`'s "no real initializer" case below supplies a dummy that a
// pre-seeded `computed = true` guarantees is never reached.
//
// "computed" tracks initialization instead of comparing `cached` against a
// sentinel `UNINITIALIZED` marker value (the approach a hand-written impl
// would normally take): `LazyImpl`'s creation-time KIR lowering constructs
// this class directly in *caller* code (to route around the trailing-lambda
// gap noted on `lazy(mode, ...)` below), so a sentinel would have to be a
// bundled `object` singleton loaded across that compilation-unit boundary --
// which this compiler's library metadata/codegen does not support for a
// zero-field `object` (its cross-module global slot is not exported; a
// compiler capability gap unrelated to KSP-491 otherwise). A plain
// caller-constructible `Boolean` sidesteps that entirely.
internal class LazyImpl<T>(
    private val initializer: () -> T,
    private val mode: LazyThreadSafetyMode,
    initialValue: Any?,
    initialComputed: Boolean
) : Lazy<T> {
    private var cached: Any? = initialValue
    private var computed: Boolean = initialComputed

    // The cast is in its own regular function, not the `value` getter body
    // directly: this compiler doesn't resolve a class type parameter (`T`)
    // referenced from inside a property getter block body (a compiler
    // capability gap unrelated to KSP-491) but does resolve it from an
    // ordinary member function body.
    @Suppress("UNCHECKED_CAST")
    private fun computeValue(): T {
        if (!computed) {
            if (mode == LazyThreadSafetyMode.SYNCHRONIZED) {
                __lazySyncLock(this)
                try {
                    if (!computed) {
                        cached = initializer()
                        computed = true
                    }
                } finally {
                    __lazySyncUnlock(this)
                }
            } else {
                // NONE / PUBLICATION: no locking bridge (KSP-491 scope). Under
                // genuine concurrent access this does not provide the safe-
                // publication guarantee real Kotlin's PUBLICATION mode makes;
                // it behaves like NONE. Single-threaded callers (this
                // compiler's diff/golden coverage) observe identical results.
                if (!computed) {
                    cached = initializer()
                    computed = true
                }
            }
        }
        return cached as T
    }

    override val value: T get() = computeValue()

    override fun isInitialized(): Boolean = computed

    override fun getValue(thisRef: Any?, property: KProperty<*>): T = value
}

public fun <T> lazy(initializer: () -> T): Lazy<T> =
    LazyImpl(initializer, LazyThreadSafetyMode.SYNCHRONIZED, null, false)

// `initializer` carries a default for the same reason `Delegates.observable`'s
// `onChange` does (see Delegates.kt): `by lazy(mode) { ... }`'s trailing lambda
// never reaches this call's argument list, so lowering supplies the real
// initializer directly when constructing the delegate object.
public fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T = { throw IllegalStateException() }): Lazy<T> =
    LazyImpl(initializer, mode, null, false)

public fun <T> lazyOf(value: T): Lazy<T> =
    LazyImpl<T>({ throw IllegalStateException("unreachable: lazyOf's value is pre-seeded") }, LazyThreadSafetyMode.NONE, value, true)
