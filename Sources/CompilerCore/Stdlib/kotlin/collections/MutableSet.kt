/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Set.kt
 * (builtins declaration of kotlin.collections.MutableSet).
 */

package kotlin.collections

// KSP-947: the nominal `MutableSet<E>` declaration is source-backed here. The
// compiler-side shell remains the fallback for contexts without the bundled
// stdlib, while its runtime-linked mutation members remain as bridges.
//
// `MutableCollection` will provide `MutableIterable` transitively when its
// separate source migration lands. Keep the direct edge here until then so
// bundled MutableSet values preserve the existing iterable type surface.
// The abstract mutation surface is inherited from MutableCollection; the
// compiler-side members retain their runtime links for the shared set box.
//
// KSP-704 (tried, reverted): a body-less interface member is unconditionally
// flagged abstract by this compiler regardless of `external`/`@KsSymbolName`
// (`MemberHeaderCollection.swift`: "Kotlin: interface functions without a
// body are implicitly abstract" — no exception for `external`). Declaring
// add/remove/clear/addAll/plusAssign/removeAll/minusAssign/retainAll here
// would force every concrete `MutableSet` implementer that does not already
// override them (`LinkedHashSet`, and `AbstractMutableMapKeys` in
// AbstractMutableMap.kt) to provide its own override, which they
// intentionally do not since they rely on this interface-level runtime
// bridge as a default implementation. Only the Swift-side registration in
// `HeaderHelpers+SyntheticSetStubs.swift` can express a body-less-but-
// non-abstract member today (see `HashSet`'s matching FQName exemption in
// `Inheritance.swift`'s `validateAbstractOverridesForDecl`). Migrating these
// members needs a compiler capability (default-implemented-but-externally-
// linked interface members) that does not exist yet.

/**
 * A generic unordered collection of elements that supports adding and removing
 * elements.
 */
public interface MutableSet<E> : Set<E>, MutableCollection<E>, MutableIterable<E>
