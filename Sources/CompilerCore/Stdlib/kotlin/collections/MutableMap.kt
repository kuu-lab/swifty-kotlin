package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-946: keep the MutableMap nominal declaration in bundled Kotlin source.
// KSP-703: remove/clear are source-backed with direct runtime links (every
// known concrete implementer — HashMap, AbstractMutableMap — already
// overrides them itself, so this compiler's "body-less interface member is
// always abstract" rule, which blocked KSP-704's MutableSet mutation
// members, does not apply here). put stays Swift-registered: its
// `.throwingFunction` ABI flag is not something the @KsSymbolName annotation
// pipeline is confirmed to propagate for interface members, and getting that
// wrong silently breaks exception propagation rather than failing the build.
// putAll also stays Swift-registered: it is on
// `BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap`'s
// whitelist as an intentional member/extension overload collision matching
// upstream Kotlin, so its interface-member registration is not simply dead
// code to fold away. put/putAll remain registered by
// `registerSyntheticMutableMapStub`, and MutableMap's own `entries` property
// by the entries-property block in that same function; Map's own
// size/keys/values/entries residuals stay in `registerMapHigherOrderMembers`
// (both in `HeaderHelpers+SyntheticMapStubs.swift`, which also remains for
// `--no-stdlib` contexts).
public interface MutableMap<K, V> : Map<K, V> {
    @IgnorableReturnValue
    @KsSymbolName("__kk_mutable_map_remove")
    public fun remove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    public fun clear()
}
