package kotlin.reflect

// MIGRATION-REFLECT-001
// KClass basic API: simpleName, qualifiedName, isInstance, isAbstract, isSealed, isFinal.
// Migration source: Sources/Runtime/RuntimeStringArray.swift
//   kk_kclass_simple_name, kk_kclass_qualified_name, kk_kclass_isInstance,
//   kk_kclass_is_abstract, kk_kclass_is_sealed, kk_kclass_is_final
//
// NOTE: Not yet wired into the compiler pipeline.
// CallTypeChecker+KClassMemberCallInference.swift and
// CallLowerer+KClassReflectMemberCalls.swift still intercept these call sites and
// rewrite them to kk_* ABI calls directly. This file is the migration target; wiring
// (and removal of the corresponding lowering entries) happens in a follow-up task.
//
// Implementation strategy:
//   - simpleName / qualifiedName — ABI bridge (reads runtime metadata registry)
//   - isInstance                 — ABI bridge (delegates to kk_op_is type-token check)
//   - isAbstract / isSealed / isFinal — ABI bridge (reads metadata flag bits)

// ─── ABI bridges ─────────────────────────────────────────────────────────────

private external fun kk_kclass_simple_name(kclass: KClass<*>): String?

private external fun kk_kclass_qualified_name(kclass: KClass<*>): String?

private external fun kk_kclass_isInstance(kclass: KClass<*>, value: Any?): Boolean

private external fun kk_kclass_is_abstract(kclass: KClass<*>): Boolean

private external fun kk_kclass_is_sealed(kclass: KClass<*>): Boolean

private external fun kk_kclass_is_final(kclass: KClass<*>): Boolean

// ─── simpleName ──────────────────────────────────────────────────────────────

/**
 * Returns the simple name of the class as it was declared in the source code,
 * or `null` if the class is anonymous.
 */
public val <T : Any> KClass<T>.simpleName: String?
    get() = kk_kclass_simple_name(this)

// ─── qualifiedName ───────────────────────────────────────────────────────────

/**
 * Returns the fully qualified dot-separated name of the class,
 * or `null` if the class is local or anonymous.
 */
public val <T : Any> KClass<T>.qualifiedName: String?
    get() = kk_kclass_qualified_name(this)

// ─── isInstance ──────────────────────────────────────────────────────────────

/**
 * Returns `true` if [value] is an instance of the class represented by this KClass.
 *
 * This is equivalent to the `is` operator for a type known at runtime.
 */
public fun <T : Any> KClass<T>.isInstance(value: Any?): Boolean =
    kk_kclass_isInstance(this, value)

// ─── isAbstract ──────────────────────────────────────────────────────────────

/**
 * Returns `true` if this class is `abstract`.
 */
public val <T : Any> KClass<T>.isAbstract: Boolean
    get() = kk_kclass_is_abstract(this)

// ─── isSealed ────────────────────────────────────────────────────────────────

/**
 * Returns `true` if this class is `sealed`.
 * All subclasses of a sealed class must be known at compile time.
 */
public val <T : Any> KClass<T>.isSealed: Boolean
    get() = kk_kclass_is_sealed(this)

// ─── isFinal ─────────────────────────────────────────────────────────────────

/**
 * Returns `true` if this class is `final` and cannot be subclassed.
 */
public val <T : Any> KClass<T>.isFinal: Boolean
    get() = kk_kclass_is_final(this)
