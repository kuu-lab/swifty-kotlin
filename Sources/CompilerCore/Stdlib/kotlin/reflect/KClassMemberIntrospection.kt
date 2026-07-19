package kotlin.reflect

import kotlin.internal.KsSymbolName

// KSP-496
// KClass member introspection: visibility, typeParameters, annotations.
// Runtime bridges live in Sources/Runtime/RuntimeReflection.swift.
//
// NOTE: `members`/`constructors`/`primaryConstructor`/`properties`/
// `memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/
// `declaredMemberFunctions`/`nestedClasses`/`supertypes` are intentionally NOT
// covered here. Investigation for KSP-496 found that casting a runtime handle
// returned by a bridge call to a `Collection<KCallable<*>>` / `KFunction<*>` /
// `List<KType>` / `Collection<KClass<*>>`-shaped interface type throws at
// runtime (`KFunction`/`KProperty`/`KType` handles are constructed directly by
// Swift runtime code and are not wired for genuine Kotlin-level `is`/`as`
// interface conformance checks — e.g. `KCallable.name` resolves to a single
// fixed `kk_kproperty_stub_name` implementation regardless of whether the
// underlying handle is actually a KFunction or a KProperty). Fixing this
// requires deeper Runtime object-model work (proper interface-conformance
// metadata / polymorphic dispatch for reflection handles) beyond this
// ticket's "thin public layer" scope, so these members remain compiler
// special cases in CallTypeChecker+KClassMemberCallInference.swift /
// CallLowerer+KClassReflectMemberCalls.swift for now.
//
// NOTE: `findAnnotation<T>()` / `findAssociatedObject<T>()` are also
// intentionally NOT covered here — they take a reified type argument, which
// this compiler currently only supports via a small compiler-side allowlist
// (see how `typeOf<T>()` is special-cased). They remain implemented as
// compiler special cases until the compiler supports general reified
// stdlib-source functions.

// ─── ABI bridges ─────────────────────────────────────────────────────────────

@KsSymbolName("__kk_kclass_visibility")
private external fun __kk_kclass_visibility(kclass: KClass<*>): String?

@KsSymbolName("__kk_kclass_type_parameters")
private external fun __kk_kclass_type_parameters(kclass: KClass<*>): List<Any?>

@KsSymbolName("__kk_kclass_get_annotations")
private external fun __kk_kclass_get_annotations(kclass: KClass<*>): List<Annotation>

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
