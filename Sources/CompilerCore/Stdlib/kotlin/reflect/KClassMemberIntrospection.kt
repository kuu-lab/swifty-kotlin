package kotlin.reflect

import kotlin.internal.KsSymbolName

// KSP-496
// KClass member introspection: visibility, typeParameters, annotations.
// Runtime bridges live in Sources/Runtime/RuntimeReflection.swift.
//
// NOTE: `members`/`constructors`/`primaryConstructor`/`properties`/
// `memberProperties`/`declaredMemberProperties`/`functions`/`memberFunctions`/
// `declaredMemberFunctions`/`nestedClasses`/`supertypes` remain compiler
// special cases because their generic public declarations are not yet bundled.
// KSP-689 wires the returned runtime handles to stable reflection nominal IDs,
// so `is`/`as` and shared `KCallable.name` dispatch are valid at the Kotlin
// boundary.
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
