/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/jvm/src/kotlin/collections/TypeAliases.kt,
 * where this name is a typealias onto java.util.LinkedHashMap.
 */

package kotlin.collections

// KSP-703: split out of CollectionAliases.kt into its own 本家-named file
// (docs/stdlib-pipeline.md §6), matching HashSet.kt/LinkedHashSet.kt's
// KSP-704 split.
//
// Structural deviation from upstream (docs/stdlib-pipeline.md §13-8;
// corrected 2026-09-15 — the original note here had the reference backwards).
// `Scripts/diff_kotlinc.sh` diffs against `kotlinc-jvm`, and on the JVM,
// `kotlin.collections.HashMap`/`LinkedHashMap` are typealiases onto the
// distinct `java.util.HashMap`/`java.util.LinkedHashMap` classes, where
// `LinkedHashMap extends HashMap` (verified empirically: `HashMap() is
// LinkedHashMap<*, *>` is false, `LinkedHashMap() is HashMap<*, *>` is true).
// kotlin-native instead makes `HashMap` the concrete class with `LinkedHashMap`
// a typealias onto it (`actual typealias LinkedHashMap<K, V> = HashMap<K,
// V>`, i.e. the same type both ways) — but kotlin-native isn't the diff
// oracle here. This codebase's HashMap.kt (KSP-1055) being the concrete class
// matches both references; LinkedHashMap aliasing the unrelated MutableMap
// interface matches neither. `HashMap()`/`LinkedHashMap()` constructor calls
// are both recognized by name and rewritten directly to runtime map-box entry
// points by `CollectionLiteralLoweringPass` (`mutableMapConstructorNames` in
// `+LookupTables+Map.swift`), so both already construct working maps; only
// the nominal class hierarchy (and thus `is` results) differ from the JVM
// reference. Promoting LinkedHashMap to `class LinkedHashMap<K, V> :
// HashMap<K, V>` (a real subclass, not a typealias, to reproduce the JVM
// reference's one-directional `is HashMap` result) is follow-up work, not
// part of KSP-703.
public typealias LinkedHashMap<K, V> = MutableMap<K, V>
