/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the
 * license/LICENSE.txt file.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-703: isEmpty/get are source-backed with direct runtime links. The
// runtime-backed property links remain residual symbols because built-in map
// boxes bypass itable registration; see SyntheticMapRuntimeResiduals.swift.
public interface Map<K, out V> {
    public val size: Int
    public val keys: Set<K>
    public val values: Collection<V>
    public val entries: Set<Map.Entry<K, V>>

    @KsSymbolName("__kk_map_is_empty")
    public fun isEmpty(): Boolean

    @KsSymbolName("__kk_map_get")
    public operator fun get(key: K): V?
}
