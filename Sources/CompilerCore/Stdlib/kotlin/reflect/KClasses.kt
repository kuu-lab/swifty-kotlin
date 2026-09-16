/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KClasses.kt.
 */

package kotlin.reflect

import kotlin.internal.KsSymbolName
// KSP-496
// KClass basic API: simpleName, qualifiedName, isInstance, cast, safeCast and
// the 12 class-kind/modifier boolean flags.
// Runtime bridges live in Sources/Runtime/RuntimeStringArray.swift.
//
// NOTE: extension *properties* use a star-projected `KClass<*>` receiver
// rather than `<T : Any> KClass<T>` — this compiler's parser does not accept
// a type-parameter list on an extension property declaration
// (`val <T> Receiver<T>.name: Type` fails with KSWIFTK-PARSE-0002). The
// extension *functions* below are unaffected and keep the precise
// `<T : Any> KClass<T>` receiver.

// ─── ABI bridges ─────────────────────────────────────────────────────────────

@KsSymbolName("__kk_kclass_simple_name")
private external fun __kk_kclass_simple_name(kclass: KClass<*>): String?

@KsSymbolName("__kk_kclass_qualified_name")
private external fun __kk_kclass_qualified_name(kclass: KClass<*>): String?

@KsSymbolName("__kk_kclass_isInstance")
private external fun __kk_kclass_isInstance(kclass: KClass<*>, value: Any?): Boolean

// `__kk_kclass_cast` is a throwing runtime entry (`isThrowing: true` in
// RuntimeABISpec+Operator.swift); ABILoweringPass appends the `outThrown`
// argument automatically, so the Kotlin declaration lists only the two value
// parameters.
@KsSymbolName("__kk_kclass_cast")
private external fun __kk_kclass_cast(kclass: KClass<*>, value: Any?): Any?

@KsSymbolName("__kk_kclass_safeCast")
private external fun __kk_kclass_safeCast(kclass: KClass<*>, value: Any?): Any?

@KsSymbolName("__kk_kclass_is_final")
private external fun __kk_kclass_is_final(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_open")
private external fun __kk_kclass_is_open(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_abstract")
private external fun __kk_kclass_is_abstract(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_data")
private external fun __kk_kclass_is_data(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_sealed")
private external fun __kk_kclass_is_sealed(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_value")
private external fun __kk_kclass_is_value(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_enum")
private external fun __kk_kclass_is_enum(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_interface")
private external fun __kk_kclass_is_interface(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_object")
private external fun __kk_kclass_is_object(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_inner")
private external fun __kk_kclass_is_inner(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_companion")
private external fun __kk_kclass_is_companion(kclass: KClass<*>): Boolean

@KsSymbolName("__kk_kclass_is_fun")
private external fun __kk_kclass_is_fun(kclass: KClass<*>): Boolean

// ─── simpleName / qualifiedName ──────────────────────────────────────────────

/**
 * Returns the simple name of the class as it was declared in the source code,
 * or `null` if the class is anonymous.
 */
public val KClass<*>.simpleName: String?
    get() = __kk_kclass_simple_name(this)

/**
 * Returns the fully qualified dot-separated name of the class,
 * or `null` if the class is local or anonymous.
 */
public val KClass<*>.qualifiedName: String?
    get() = __kk_kclass_qualified_name(this)

// ─── isInstance ──────────────────────────────────────────────────────────────

/**
 * Returns `true` if [value] is an instance of the class represented by this KClass.
 */
public fun <T : Any> KClass<T>.isInstance(value: Any?): Boolean =
    __kk_kclass_isInstance(this, value)

// ─── cast / safeCast ─────────────────────────────────────────────────────────

/**
 * Casts [value] to the class represented by this KClass,
 * or throws a `ClassCastException` if it is not an instance of it.
 */
public fun <T : Any> KClass<T>.cast(value: Any?): T =
    __kk_kclass_cast(this, value) as T

/**
 * Casts [value] to the class represented by this KClass,
 * or returns `null` if it is not an instance of it.
 */
public fun <T : Any> KClass<T>.safeCast(value: Any?): T? =
    __kk_kclass_safeCast(this, value) as T?

// ─── boolean class-kind / modifier flags ─────────────────────────────────────

/** Returns `true` if this class is `final` and cannot be subclassed. */
public val KClass<*>.isFinal: Boolean
    get() = __kk_kclass_is_final(this)

/** Returns `true` if this class is `open`. */
public val KClass<*>.isOpen: Boolean
    get() = __kk_kclass_is_open(this)

/** Returns `true` if this class is `abstract`. */
public val KClass<*>.isAbstract: Boolean
    get() = __kk_kclass_is_abstract(this)

/** Returns `true` if this class is a `data` class. */
public val KClass<*>.isData: Boolean
    get() = __kk_kclass_is_data(this)

/**
 * Returns `true` if this class is `sealed`.
 * All subclasses of a sealed class must be known at compile time.
 */
public val KClass<*>.isSealed: Boolean
    get() = __kk_kclass_is_sealed(this)

/** Returns `true` if this class is a `value` (inline) class. */
public val KClass<*>.isValue: Boolean
    get() = __kk_kclass_is_value(this)

/** Returns `true` if this class is an `enum` class. */
public val KClass<*>.isEnum: Boolean
    get() = __kk_kclass_is_enum(this)

/** Returns `true` if this class is an interface. */
public val KClass<*>.isInterface: Boolean
    get() = __kk_kclass_is_interface(this)

/** Returns `true` if this class is an `object` declaration. */
public val KClass<*>.isObject: Boolean
    get() = __kk_kclass_is_object(this)

/** Returns `true` if this class is an inner class. */
public val KClass<*>.isInner: Boolean
    get() = __kk_kclass_is_inner(this)

/** Returns `true` if this class is a companion object. */
public val KClass<*>.isCompanion: Boolean
    get() = __kk_kclass_is_companion(this)

/** Returns `true` if this class is a functional (`fun`) interface. */
public val KClass<*>.isFun: Boolean
    get() = __kk_kclass_is_fun(this)

// KSP-496
// KClass member introspection: visibility, typeParameters, annotations, and
// the KCallable/KFunction/KProperty-returning collection accessors.
// Runtime bridges live in Sources/Runtime/RuntimeReflection.swift and
// Sources/Runtime/RuntimeStringArray.swift.
//
// NOTE: the collection accessors below (`members`, `constructors`, etc.)
// return `List<Any?>` rather than their real stdlib signatures (e.g.
// `Collection<KCallable<*>>`) — the returned runtime handles carry stable
// reflection nominal IDs (KSP-689), so `is`/`as` and shared `KCallable` metadata
// dispatch are valid at the Kotlin boundary, but the containing collection
// itself is not yet precisely typed.
//
// NOTE: `findAnnotation<T>()` / `findAssociatedObject<T>()` are NOT covered
// here — they take a reified type argument, which this compiler only
// supports for a fixed, non-nested set of built-in intrinsics (see how
// `typeOf<T>()` is special-cased). Forwarding a reified type parameter as
// the type argument of a *nested* reified call is not yet general, so they
// remain compiler special cases (Sources/CompilerCore/KIR/CallLowerer+KClassReflectMemberCalls.swift).
//
// NOTE: `properties` is also NOT covered here, unlike its `memberProperties`/
// `declaredMemberProperties` siblings. It is not a real kotlin-stdlib name
// (only the `member`/`declaredMember`-prefixed variants exist upstream), and
// Scripts/diff_cases/kclass_interface_handles.kt relies on being able to
// freely shadow it with a real user-declared extension for kotlinc
// portability. It remains a compiler special case so user shadowing keeps
// working exactly as before.

// ─── ABI bridges ─────────────────────────────────────────────────────────────

@KsSymbolName("__kk_kclass_visibility")
private external fun __kk_kclass_visibility(kclass: KClass<*>): String?

@KsSymbolName("__kk_kclass_type_parameters")
private external fun __kk_kclass_type_parameters(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_get_annotations")
private external fun __kk_kclass_get_annotations(kclass: KClass<*>): List<Annotation>

@KsSymbolName("__kk_kclass_members")
private external fun __kk_kclass_members(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_constructors")
private external fun __kk_kclass_constructors(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_nested_classes")
private external fun __kk_kclass_nested_classes(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_primary_constructor")
private external fun __kk_kclass_primary_constructor(kclass: KClass<*>): Any?

@KsSymbolName("__kk_kclass_member_properties")
private external fun __kk_kclass_member_properties(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_declared_member_properties")
private external fun __kk_kclass_declared_member_properties(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_functions")
private external fun __kk_kclass_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_member_functions")
private external fun __kk_kclass_member_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_declared_member_functions")
private external fun __kk_kclass_declared_member_functions(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_supertypes")
private external fun __kk_kclass_supertypes(kclass: KClass<*>): List<Any?>

// ─── visibility / typeParameters / annotations ───────────────────────────────

/** Returns the visibility of this class, or `null` if unknown. */
public val KClass<*>.visibility: String?
    get() = __kk_kclass_visibility(this)

/** Returns the type parameters of this class. */
public val KClass<*>.typeParameters: List<Any?>
    get() = __kk_kclass_type_parameters(this)

/** Returns all annotations present on this class. */
public val KClass<*>.annotations: List<Annotation>
    get() = __kk_kclass_get_annotations(this)

// ─── member / constructor / supertype collections ────────────────────────────

/** Returns all functions and properties declared in this class and its supertypes. */
public val KClass<*>.members: List<Any?>
    get() = __kk_kclass_members(this)

/** Returns the constructors declared in this class. */
public val KClass<*>.constructors: List<Any?>
    get() = __kk_kclass_constructors(this)

/** Returns the classes declared directly inside this class. */
public val KClass<*>.nestedClasses: List<Any?>
    get() = __kk_kclass_nested_classes(this)

/** Returns the primary constructor of this class, or `null` if it has none. */
public val KClass<*>.primaryConstructor: Any?
    get() = __kk_kclass_primary_constructor(this)

/** Returns all non-extension member properties declared in this class and its supertypes. */
public val KClass<*>.memberProperties: List<Any?>
    get() = __kk_kclass_member_properties(this)

/** Returns non-extension member properties declared directly in this class, excluding supertypes. */
public val KClass<*>.declaredMemberProperties: List<Any?>
    get() = __kk_kclass_declared_member_properties(this)

/** Returns all non-extension functions declared in this class and its supertypes. */
public val KClass<*>.functions: List<Any?>
    get() = __kk_kclass_functions(this)

/** Returns all non-extension member functions declared in this class and its supertypes. */
public val KClass<*>.memberFunctions: List<Any?>
    get() = __kk_kclass_member_functions(this)

/** Returns non-extension member functions declared directly in this class, excluding supertypes. */
public val KClass<*>.declaredMemberFunctions: List<Any?>
    get() = __kk_kclass_declared_member_functions(this)

/** Returns the immediate supertypes of this class. */
public val KClass<*>.supertypes: List<Any?>
    get() = __kk_kclass_supertypes(this)
