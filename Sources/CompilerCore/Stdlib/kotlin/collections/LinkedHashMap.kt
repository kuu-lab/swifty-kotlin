/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/TypeAliases.kt,
 * where this name is a typealias onto java.util.LinkedHashMap.
 */

package kotlin.collections

// KSP-703: split out of CollectionAliases.kt into its own upstream-named file
// (docs/stdlib-pipeline.md §6), matching HashSet.kt/LinkedHashSet.kt's
// KSP-704 split.
//
// Structural deviation from upstream (docs/stdlib-pipeline.md §13-8): in
// kotlin-native, `LinkedHashMap` is the concrete class and `HashMap` is a
// typealias onto it (`actual typealias HashMap<K, V> = LinkedHashMap<K, V>`).
// This codebase has the shape inverted — HashMap.kt (KSP-1055) is the
// concrete, @KsSymbolName-bridged class, while LinkedHashMap remains a plain
// typealias onto the MutableMap interface. `HashMap()`/`LinkedHashMap()`
// constructor calls are both recognized by name and rewritten directly to
// runtime map-box entry points by `CollectionLiteralLoweringPass`
// (`mutableMapConstructorNames` in `+LookupTables+Map.swift`), so both
// already construct working (if identically-shaped) maps; only the nominal
// class hierarchy differs from upstream. Giving LinkedHashMap the same
// concrete-class treatment as LinkedHashSet — and inverting this alias
// direction to match upstream — is follow-up work, not part of KSP-703.
public typealias LinkedHashMap<K, V> = MutableMap<K, V>
