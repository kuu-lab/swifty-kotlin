/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Reproduces the observable class hierarchy of kotlin-stdlib
 * jvm/src/kotlin/collections/TypeAliases.kt's `LinkedHashMap` typealias onto
 * java.util.LinkedHashMap, which extends java.util.HashMap.
 */

package kotlin.collections

// KSP-703: split out of CollectionAliases.kt into its own 本家-named file
// (docs/stdlib-pipeline.md §6), matching HashSet.kt/LinkedHashSet.kt's
// KSP-704 split.
//
// KUU-556: promoted from a `MutableMap` typealias to a real `HashMap`
// subclass, matching the diff oracle (`kotlinc-jvm`, where
// `java.util.LinkedHashMap extends java.util.HashMap` as distinct classes —
// verified empirically: `HashMap() is LinkedHashMap<*, *>` is false,
// `LinkedHashMap() is HashMap<*, *>` is true). kotlin-native instead aliases
// `LinkedHashMap` onto `HashMap` (the same type both ways), but that target
// isn't the diff oracle here (see docs/stdlib-pipeline.md §13-8, corrected
// 2026-09-15 after the KSP-703 memo initially had this backwards).
//
// All members are inherited from HashMap unchanged: both sit on the same
// RuntimeMapBox-backed storage, and HashMap already provides every Map/
// MutableMap member with a real body (no reliance on Swift-side synthetic
// member registration the way HashSet.kt does), so there is nothing for this
// subclass to override.
//
// Constructor shape (KUU-557 tracks this as a standalone compiler-capability
// gap): HashMap's four constructors (), (Int), (Int, Float) and
// (Map<out K, V>) can't be mirrored 1:1 as secondary constructors delegating
// via `: super(...)` -- this compiler's generic type-argument inference for a
// `this(...)`/`super(...)` delegating call only succeeds when an argument's
// *type* mentions the class's own type parameters (as the Map<out K, V> copy
// constructor's does); a delegating call with only Int/Float/no arguments
// fails with KSWIFTK-SEMA-INFER regardless of target, even when the argument
// *values* would obviously work. Only the primary constructor's inline
// `: HashMap<K, V>(...)` header position is exempt (its substitution comes
// from the supertype clause, not general inference), so the (), (Int) and
// (Int, Float) forms are collapsed into one primary constructor with default
// parameters; the copy constructor is the one secondary constructor whose
// argument type qualifies, so it delegates via `super(original)` directly.
// None of these bodies ever run for real: `HashMap(...)`/`LinkedHashMap(...)`
// call expressions are always intercepted by name and rewritten straight to
// runtime map-box entry points (`mutableMapConstructorNames` in
// `CollectionLiteralLoweringPass+LookupTables+Map.swift`), matching how
// HashMap.kt's own four constructors are likewise all empty.
public class LinkedHashMap<K, V>(
    initialCapacity: Int = 0,
    loadFactor: Float = 1.0f
) : HashMap<K, V>(initialCapacity, loadFactor) {
    constructor(original: Map<out K, V>) : super(original)
}
