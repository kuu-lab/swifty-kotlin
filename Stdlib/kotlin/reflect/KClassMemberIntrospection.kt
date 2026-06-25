package kotlin.reflect

// MIGRATION-REFLECT-002
// KClass member introspection: members, constructors, nestedClasses, supertypes.
// Migration source: Sources/Runtime/RuntimeStringArray.swift
//   kk_kclass_members, kk_kclass_constructors, kk_kclass_supertypes,
//   kk_kclass_nested_classes
//
// NOTE: Not yet wired into the compiler pipeline.
// CallLowerer+KClassReflectMemberCalls.swift still dispatches these properties
// directly to the kk_* ABI functions via special-case lowering.
// This file is the migration target; wiring (and removal of the corresponding
// special-case entries in CallLowerer+KClassReflectMemberCalls.swift and
// CallTypeChecker+KClassMemberCallInference.swift) happens in a follow-up task.
//
// Implementation strategy:
//   members         — delegates to __kk_kclass_members (maps to kk_kclass_members).
//                     Returns KCallable handles registered via kk_kclass_register_member.
//   constructors    — delegates to __kk_kclass_constructors (maps to kk_kclass_constructors).
//                     Returns KConstructor handles registered via kk_kconstructor_create.
//   supertypes      — delegates to __kk_kclass_supertypes (maps to kk_kclass_supertypes).
//                     Currently returns a list of supertype name strings (not KType objects);
//                     full KType-backed implementation requires a separate runtime upgrade.
//   nestedClasses   — delegates to __kk_kclass_nested_classes (maps to kk_kclass_nested_classes).
//                     Returns an empty list until nested class metadata registration is
//                     implemented (the compiler does not yet emit nested class handles
//                     to the runtime).

/**
 * Returns all non-extension callable members of this class:
 * all declared and inherited functions and properties.
 */
val <T : Any> KClass<T>.members: Collection<KCallable<*>>
    get() = this.__kk_kclass_members()

/**
 * Returns all constructors declared in this class.
 */
val <T : Any> KClass<T>.constructors: Collection<KFunction<T>>
    get() = @Suppress("UNCHECKED_CAST") (this.__kk_kclass_constructors() as Collection<KFunction<T>>)

/**
 * Returns the list of immediate supertypes of this class.
 * The returned KType objects represent the direct base class and implemented interfaces.
 */
val <T : Any> KClass<T>.supertypes: List<KType>
    get() = @Suppress("UNCHECKED_CAST") (this.__kk_kclass_supertypes() as List<KType>)

/**
 * Returns all classes nested inside this class.
 */
val <T : Any> KClass<T>.nestedClasses: Collection<KClass<*>>
    get() = @Suppress("UNCHECKED_CAST") (this.__kk_kclass_nested_classes() as Collection<KClass<*>>)
