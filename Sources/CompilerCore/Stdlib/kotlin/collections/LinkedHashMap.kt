/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Reproduces the observable class hierarchy of kotlin-stdlib
 * jvm/src/kotlin/collections/TypeAliases.kt's `LinkedHashMap` typealias onto
 * java.util.LinkedHashMap, which extends java.util.HashMap.
 */

package kotlin.collections

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
// (Map<out K, V>) are mirrored 1:1 as secondary constructors delegating via
// `: super(...)`, matching java/util/Hashtable.kt's shape. KUU-4500:
// java.util.LinkedHashMap's third constructor parameter is `accessOrder`;
// when true, get/put reorder entries least-recently-used first (the runtime
// box implements it; see `__kk_map_set_access_order` and
// `RuntimeMapBox.recordAccess`). The flag is accepted for signature
// compatibility and forwarded nowhere: constructor calls are intercepted by
// name and rewritten straight to runtime map-box entry points
// (`mutableMapConstructorNames` in
// `CollectionLiteralLoweringPass+LookupTables+Map.swift`), matching how
// HashMap.kt's own four constructors are likewise all empty.
// KUU-1944: the JVM-compatible LinkedHashMap contract permits user subclasses.
public open class LinkedHashMap<K, V> : HashMap<K, V> {
    constructor() : super()
    constructor(initialCapacity: Int) : super(initialCapacity)
    constructor(initialCapacity: Int, loadFactor: Float) : super(initialCapacity, loadFactor)
    constructor(initialCapacity: Int, loadFactor: Float, accessOrder: Boolean) : super(initialCapacity, loadFactor)
    constructor(original: Map<out K, V>) : super(original)
}
