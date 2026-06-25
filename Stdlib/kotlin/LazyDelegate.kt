package kotlin

// MIGRATION-PROP-002
// lazy delegate API: Lazy<out T> interface, LazyThreadSafetyMode enum,
// lazy() and lazyOf() factory functions.
//
// Migration source:
//   Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPropertyDelegateStubs.swift
//     (registerSyntheticPropertyInterfaceStubs: Lazy<T> stubs, lazy/lazyOf synthetic functions,
//      registerLazyThreadSafetyModeStub: LazyThreadSafetyMode enum stub)
//   Sources/Runtime/RuntimeDelegates.swift
//     (kk_lazy_create, kk_lazy_of, kk_lazy_get_value, kk_lazy_is_initialized)
//   Sources/Runtime/RuntimeTypes.swift
//     (LazyThreadSafetyMode enum, RuntimeLazyBox)
//   Sources/CompilerCore/Lowering/StdlibDelegateLoweringPass.swift
//     (StdlibDelegateKind.lazy case, init-arg selection for 1-arg vs 2-arg lazy)
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// StdlibDelegateLoweringPass intercepts `by lazy {}` call sites and rewrites
// them to kk_lazy_create ABI calls. The synthetic stubs in
// HeaderHelpers+SyntheticPropertyDelegateStubs.swift continue to provide type
// information until this file is loaded. Wiring (and removal of those stubs)
// happens in RF-STDLIB-004+.
//
// Implementation strategy:
//   - LazyThreadSafetyMode — pure Kotlin enum (ordinals: SYNCHRONIZED=0,
//                            PUBLICATION=1, NONE=2; matches Kotlin stdlib order)
//   - Lazy<out T>           — pure Kotlin interface with value + isInitialized()
//   - lazy(initializer)     — cannot use `private external` (takes a compiled
//                             fn pointer); pure Kotlin SynchronizedLazyImpl fallback
//   - lazy(mode, initializer) — same; routes by mode at Kotlin level
//   - lazyOf(value)         — pure Kotlin AlreadyInitializedLazyImpl fallback
//                             (current ABI path: kk_lazy_of via sema external link)

// ─── LazyThreadSafetyMode ────────────────────────────────────────────────────

/**
 * Specifies how a [Lazy] instance synchronizes initialization among multiple threads.
 *
 * ABI note: Runtime rawValues (kk_lazy_create mode arg) are
 * NONE=0, SYNCHRONIZED=1, PUBLICATION=2 (Swift LazyThreadSafetyMode).
 * The lowering pass maps compiler-option enum to these rawValues directly.
 * When `lazy(mode, { })` is wired, ordinal-to-rawValue conversion will be
 * performed by the lowering pass.
 */
public enum class LazyThreadSafetyMode {
    /**
     * Locks access during initialization so only one thread can initialize the [Lazy] instance at a time.
     */
    SYNCHRONIZED,

    /**
     * Initializer function may be called several times on concurrent access to an uninitialized
     * [Lazy] instance value, but only the first returned value will be used.
     */
    PUBLICATION,

    /**
     * No locks are used to synchronize access to the [Lazy] instance value.
     * This mode should not be used unless guaranteed single-threaded initialization.
     */
    NONE
}

// ─── Lazy<out T> interface ────────────────────────────────────────────────────

/**
 * Represents a value with lazy initialization.
 *
 * To create an instance of [Lazy] use the [lazy] function.
 */
public interface Lazy<out T> {
    /** The lazily-initialized value of the [Lazy] instance. */
    val value: T

    /**
     * Returns `true` if a value for this [Lazy] instance has been already initialized,
     * and `false` otherwise.
     */
    fun isInitialized(): Boolean
}

// ─── Sentinel for uninitialized state ────────────────────────────────────────

private object UninitializedValue

// ─── SynchronizedLazyImpl ────────────────────────────────────────────────────
//
// Used for SYNCHRONIZED and PUBLICATION modes.
// Thread-safety in the pure-Kotlin fallback path is best-effort (no lock);
// actual thread-safety is enforced by the ABI runtime (kk_lazy_create with
// the appropriate mode rawValue).

private class SynchronizedLazyImpl<T>(private val initializer: () -> T) : Lazy<T> {
    private var _value: Any? = UninitializedValue

    override val value: T
        get() {
            if (_value === UninitializedValue) {
                _value = initializer()
            }
            @Suppress("UNCHECKED_CAST")
            return _value as T
        }

    override fun isInitialized(): Boolean = _value !== UninitializedValue
}

// ─── UnsafeLazyImpl (NONE mode) ──────────────────────────────────────────────

private class UnsafeLazyImpl<T>(private val initializer: () -> T) : Lazy<T> {
    private var _value: Any? = UninitializedValue

    override val value: T
        get() {
            if (_value === UninitializedValue) {
                _value = initializer()
            }
            @Suppress("UNCHECKED_CAST")
            return _value as T
        }

    override fun isInitialized(): Boolean = _value !== UninitializedValue
}

// ─── AlreadyInitializedLazyImpl (lazyOf) ─────────────────────────────────────

private class AlreadyInitializedLazyImpl<T>(override val value: T) : Lazy<T> {
    override fun isInitialized(): Boolean = true
}

// ─── Factory functions ────────────────────────────────────────────────────────

/**
 * Creates a new instance of the [Lazy] that is already initialized with the specified [value].
 *
 * ABI note: wired to kk_lazy_of via sema external link name until RF-STDLIB-004+.
 */
public fun <T> lazyOf(value: T): Lazy<T> = AlreadyInitializedLazyImpl(value)

/**
 * Creates a new instance of the [Lazy] that uses the specified [initializer] function and
 * [LazyThreadSafetyMode.SYNCHRONIZED] thread-safety mode.
 *
 * The initializer is called the first time [Lazy.value] is accessed; subsequent accesses
 * return the cached result.
 *
 * ABI note: cannot use `private external` (takes a compiled fn pointer).
 * StdlibDelegateLoweringPass rewrites `by lazy { }` call sites to kk_lazy_create
 * until RF-STDLIB-004+.
 */
public fun <T> lazy(initializer: () -> T): Lazy<T> = SynchronizedLazyImpl(initializer)

/**
 * Creates a new instance of the [Lazy] that uses the specified [initializer] function
 * and thread-safety [mode].
 *
 * ABI note: StdlibDelegateLoweringPass handles the 2-arg form (callArgs[1] = initFnPtr);
 * the explicit [mode] is currently mapped through the compiler-option rawValue. Full
 * ordinal-to-rawValue conversion is deferred to RF-STDLIB-004+.
 */
public fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T> = when (mode) {
    LazyThreadSafetyMode.SYNCHRONIZED, LazyThreadSafetyMode.PUBLICATION -> SynchronizedLazyImpl(initializer)
    LazyThreadSafetyMode.NONE -> UnsafeLazyImpl(initializer)
}
