// WasmEmitter.swift — KIR → WebAssembly binary.
//
// Value model: every KIR value is an i64. Heap objects are linear-memory
// addresses; every box stores its nominal type ID at offset -16 and its
// slot count (array length / object layoutWords) at offset -8. For objects,
// slot 0 (base+0) holds the interface-dispatch map and slot 1 (base+8) the
// vtable pointer, leaving user fields at slot 2+ exactly like the native
// kk_array_get_inbounds layout. Primitive boxing is the identity while all
// values are raw i64s, and the thrown channel is a single i64 global instead
// of the trailing outThrown pointer.

import Foundation
import CompilerCore

public enum WasmEmitterError: Error, CustomStringConvertible {
    case nonLaminarControlFlow(String)

    public var description: String {
        switch self {
        case let .nonLaminarControlFlow(name):
            "wasm emitter: non-laminar control flow in '\(name)'"
        }
    }
}

public struct WasmEmissionResult: Sendable {
    public let bytes: [UInt8]
    public let stubbedCallees: [String]
    public let notes: [String]
}

/// Shared emission state for one module. Function bodies are emitted by
/// `WasmFunctionEmission` (see WasmEmitter+Function.swift); runtime helpers
/// are hand-assembled in WasmEmitter+Runtime.swift.
final class WasmModuleContext {
    let module = WasmModule()
    let kir: KIRModule
    let interner: StringInterner
    let symbols: SymbolTable?
    let types: TypeSystem?
    let isWASI: Bool

    // Symbol/name → function index resolution.
    var functionIndexBySymbol: [SymbolID: Int] = [:]
    var functionIndexByNameArity: [String: Int] = [:]
    /// Helpers are keyed by `name/arity`: some runtime names overload by
    /// arity (`__kk_throwable_new` takes 0 or 1 args), and a wasm function's
    /// signature is fixed at creation, so each arity needs its own entry.
    var helperIndexByName: [String: Int] = [:]
    var stubIndexByNameArity: [String: Int] = [:]
    var importIndexByName: [String: Int] = [:]

    var globalIndexBySymbol: [SymbolID: Int] = [:]
    var paramIndexBySymbolByFunction: [SymbolID: [Int32: Int]] = [:]

    // Runtime globals (indices into the module's global section).
    var thrownGlobal = -1
    var heapGlobal = -1
    var edgeHeadGlobal = -1
    var dataEndGlobal = -1

    // Lazily-created WASI imports (only when isWASI).
    var fdWriteImport = -1
    var procExitImport = -1

    // Bump cursor for static data (string literal bytes); heap follows.
    var dataCursor: Int64 = WasmLayout.dataStart
    var stringOffsetByLiteral: [InternedString: Int64] = [:]

    var stubbedCallees: [String] = []
    var notes: [String] = []

    init(kir: KIRModule, interner: StringInterner, symbols: SymbolTable?, types: TypeSystem?, isWASI: Bool) {
        self.kir = kir
        self.interner = interner
        self.symbols = symbols
        self.types = types
        self.isWASI = isWASI
    }

    enum WasmLayout {
        /// Bytes [0, dataStart) are runtime scratch space (iovecs, newline).
        static let dataStart: Int64 = 1024
        /// iovec base for WASI writes.
        static let iovecAddress: Int64 = 8
        static let nwrittenAddress: Int64 = 24
        static let newlineAddress: Int64 = 32
        /// Byte offset of the nominal type ID relative to a box base.
        static let typeIDOffset: Int64 = -16
        /// Byte offset of the slot count (array length / object layoutWords).
        static let metaOffset: Int64 = -8
        /// Body slot 1: the object's vtable pointer (arrays use it as
        /// element 1 — the two never collide because dispatch never runs on
        /// plain arrays).
        static let vtableSlotOffset: Int64 = 8
        /// Reserved class IDs for runtime-internal box kinds.
        static let arrayTypeID: Int64 = -9_001
        static let stringTypeID: Int64 = -9_002
        /// Kotlin `List` box (read-only views from `listOf`/`toList`).
        static let listTypeID: Int64 = -9_010
        /// Kotlin `MutableList`/`ArrayList` box (`mutableListOf`/`arrayListOf`).
        static let arrayListTypeID: Int64 = -9_011
        /// `kk_list_iterator` result box.
        static let listIteratorTypeID: Int64 = -9_012
        /// List/iterator body slot offsets (object slots 2/3/4): slot2 holds
        /// the backing array (or the list, for iterators), slot3 the element
        /// count (or iterator index), slot4 flags (or expected modCount).
        static let listArrayOffset: Int64 = 16
        static let listCountOffset: Int64 = 24
        static let listFlagsOffset: Int64 = 32
        /// `subList` view box: `{backing@16, size@24, flags@32, parent@40,
        /// expectedParentMod@48}`. Backing is the root parent's array pointer
        /// pre-adjusted by `from*8`, so all element reads work unchanged.
        static let listViewTypeID: Int64 = -9_017
        /// `kotlinx.coroutines.NonCancellable`'s nominal tag — the same
        /// FNV-1a `stableNominalTypeID` payload the KIR initializer bodies
        /// embed, so `is` checks and itable lookups match the singleton the
        /// `kk_non_cancellable_instance` helper lazily allocates.
        static let nonCancellableTypeID: Int64 = 8_366_687_476_779_162
        static let listParentOffset: Int64 = 40
        static let listExpectedModOffset: Int64 = 48
        /// flags bit layout (list/set/view boxes): bit0 = readOnly,
        /// bit1 = view marker, bits 8+ = modCount (structural-mod epoch).
        static let listViewFlag: Int64 = 0x2
        static let modCountShift: Int64 = 8
        /// `kk_map_iterator` result box.
        static let mapIteratorTypeID: Int64 = -9_013
        /// `kk_mutable_map_iterator` result box.
        static let mutableMapIteratorTypeID: Int64 = -9_014
        /// `__kk_range_for_in_iterator` result box: `{cur@16, last@24, step@32}`.
        static let rangeForInIteratorTypeID: Int64 = -9_015
        /// `kk_function_create_N` function-value box:
        /// `{fnTableIdx@16, closure@24, arity@32, description@40}`.
        static let functionValueTypeID: Int64 = -9_016
        /// Function-value box field offsets.
        static let functionFnIdxOffset: Int64 = 16
        static let functionClosureOffset: Int64 = 24
        static let functionArityOffset: Int64 = 32
        static let functionDescOffset: Int64 = 40
        /// `kk_enum_box_ordinal` enum entry box: `{ordinal@16, name@24,
        /// classID@32}`.
        static let enumEntryTypeID: Int64 = -9_018
        /// Token-keyed metadata registry record produced by
        /// `$__kk_wasm_token_record`: `{token@16, s0@24, s1@32, s2@40, s3@48,
        /// pad@56..72, regHead@80}`. The s* slots are domain-local: for a
        /// typeToken record s0 caches the KClass/KTypeParameter box, s1 the
        /// value-class toString fn, s2 the enum values array; for an
        /// object-handle record s0/s1/s2 hold the toString/equals/hashCode
        /// overrides registered via `kk_object_register_*`.
        static let metaRecordTypeID: Int64 = -9_019
        /// Registration node in a record's regHead list:
        /// `{kind@16, argc@24, a0@32..a7@88, next@96}`.
        static let regEntryTypeID: Int64 = -9_020
        /// `kotlin.reflect.KClass` box: `{token@16, name@24, displayName@32,
        /// ..., regHead@80}` — same head offset as metadata records so
        /// `reglist_add` works uniformly.
        static let kclassTypeID: Int64 = -9_021
        /// `kotlin.reflect.KType` box: `{classifier@16, args@24, nullable@32}`.
        static let ktypeTypeID: Int64 = -9_022
        /// `kotlin.reflect.KTypeProjection` box: `{type@16, variance@24}`.
        static let ktypeProjectionTypeID: Int64 = -9_023
        /// `kotlin.reflect.KTypeParameter` box:
        /// `{identity@16, name@24, variance@32, isReified@40, upperBounds@48}`.
        static let ktypeParameterTypeID: Int64 = -9_024
        /// `kotlin.reflect.KParameter` box: `{index@16, name@24, type@32,
        /// flags@40, kind@48, typeToken@56, callableOwner@64,
        /// arrayComponent@72}`.
        static let kparameterTypeID: Int64 = -9_025
        /// `kotlin.reflect.KProperty` stub box: `{name@16, returnType@24}`.
        static let kpropertyStubTypeID: Int64 = -9_026
        /// `kotlin.reflect.KFunction` box: `{name@16, arity@24,
        /// returnType@32, flags@40, fnPtr@48, closure@56}`.
        static let kfunctionTypeID: Int64 = -9_027
        /// `kotlin.reflect.KConstructor` box: `{name@16, arity@24,
        /// returnType@32, fnPtr@40, isPrimary@48, visibility@56, kclass@64,
        /// callable@72, paramHead@80}` — paramHead reuses the regHead offset.
        static let kconstructorTypeID: Int64 = -9_028
        /// Registration-list head offset shared by metadata records, KClass
        /// boxes and KConstructor boxes (`kk_object_new(11..13)` keeps that
        /// slot free).
        static let regHeadOffset: Int64 = 80
        /// Set boxes share the list layout `{array@16, count@24, flags@32}`
        /// so `kk_list_iterator` iterates them unchanged. Concrete nominal
        /// tags come from `stableNominalTypeID` so `is` checks work.
        /// Map box slots: keys@16, values@24, count@32, flags@40.
        static let mapKeysOffset: Int64 = 16
        static let mapValuesOffset: Int64 = 24
        static let mapCountOffset: Int64 = 32
        static let mapFlagsOffset: Int64 = 40
        /// Pair/MapEntry box slots: first@16, second@24, mapRef@32,
        /// mapKey@40. A nonzero mapRef makes `second` a live `map[key]` view.
        static let pairFirstOffset: Int64 = 16
        static let pairSecondOffset: Int64 = 24
        static let pairMapRefOffset: Int64 = 32
        static let pairMapKeyOffset: Int64 = 40
        /// vtable array holds direct method slots only. itable entries live
        /// in a separate per-object buffer whose pointer is stored in the
        /// vtable header at `vt + vtableItablePtrOffset` — mirroring native's
        /// disjoint vtable/itable keyspaces so a class whose direct vtable
        /// exceeds any fixed prefix cannot clobber interface entries.
        static let vtableItablePtrOffset: Int64 = -16
        /// Direct-slot capacity of the lazily allocated vtable array.
        static let vtableSlots = 528
        /// itable buffer geometry: ifaceSlot-major with `itableStride` method
        /// slots per interface, up to `itableBlocks` interfaces per object.
        static let itableStride = 32
        static let itableBlocks = 16
        static let itableSlots = itableStride * itableBlocks // 512 entries
        /// Per-object interface map capacity (typeID, slot) pairs.
        static let ifaceMapCapacity = 8
        /// Tagged small-int sentinels must never look like real pointers.
        static let nullSentinel: Int64 = Int64.min
    }

    func emitFunctions() -> [KIRFunction] {
        var result: [KIRFunction] = []
        for decl in kir.arena.declarations {
            guard case let .function(function) = decl, !function.isInlineOnly else { continue }
            result.append(function)
        }
        return result
    }

    func resolveCallee(
        name: String,
        symbol: SymbolID?,
        argumentCount: Int,
        argumentTypes: [TypeID?] = []
    ) -> CalleeResolution {
        // Runtime-lowered names must win over a retained source symbol: the
        // symbol can be stale bookkeeping for inline expansion while the kk_*
        // text is the real target (mirrors NativeEmitter's contract).
        // `kk_lambda_<id>` is the exception — the retained symbol *is* the
        // lowered lambda body (same carve-out as the native emitter).
        // `kk_fn_*` is the kklib link-name form: its symbol points at the
        // klib-materialized body this module already emits, so `.direct`
        // resolution applies (unlike `kk_op_*`/`__kk_*` helper names).
        let isRuntimeName = (name.hasPrefix("kk_") || name.hasPrefix("__kk_") || name.hasPrefix("$"))
            && !name.hasPrefix("kk_lambda_")
            && !name.hasPrefix("kk_fn_")
        if !isRuntimeName,
           let symbol,
           let index = functionIndexBySymbol[symbol]
        {
            return .direct(index)
        }
        if !isRuntimeName,
           symbol == nil,
           let index = functionIndexByNameArity["\(name)/\(argumentCount)"]
        {
            return .direct(index)
        }
        if WasmRuntimeHelpers.isEmittedHelperName(name) {
            return .emittedHelper(emittedHelperIndex(for: name, argumentCount: argumentCount))
        }
        if let index = helperIndexByName["\(name)/\(argumentCount)"] {
            return .emittedHelper(index)
        }
        // Stdlib bodies live in the .kklib, not this module — a handful have
        // direct wasm intrinsics (kotlin.io.println forwards to the raw WASI
        // writer, exactly as its bundled body does via __printlnStringRaw).
        if let helper = stdlibIntrinsicName(symbol: symbol, argumentCount: argumentCount) {
            return .emittedHelper(emittedHelperIndex(for: helper, argumentCount: argumentCount))
        }
        // `$default` forwarders and other symbol-less stdlib shims only carry
        // their callee name — route the known ones onto the same helpers the
        // fqName path selects. `argumentTypes` disambiguates same-named
        // overloads (e.g. `indexOf(String,…)` vs `indexOf(Char,…)`).
        if let helper = stdlibShimName(for: name, argumentTypes: argumentTypes) {
            return .emittedHelper(emittedHelperIndex(for: helper, argumentCount: argumentCount))
        }
        // Direct calls onto stdlib members whose bodies live in the .kklib
        // (e.g. a `size` getter on a sentinel-boxed map) resolve through the
        // same thunk table vtable/itable registrations use, instead of
        // silently stubbing to 0.
        if let symbol, let thunk = memberThunkInfo(for: symbol) {
            return .emittedHelper(
                emittedHelperIndex(for: thunk.helper, argumentCount: thunk.arity)
            )
        }
        // `kk_fn_<name>_s<id>__<ns>` link names whose bodies were materialized
        // from the artifact's inline-kir resolve to the decl's bare name —
        // demangle synthetic (`__*`) init-family names for symbol-less calls.
        if name.hasPrefix("kk_fn___") {
            var inner = String(name.dropFirst(6))
            if let range = inner.range(of: "__", options: .backwards) {
                inner = String(inner[..<range.lowerBound])
            }
            if let range = inner.range(of: "_s", options: .backwards),
               range.upperBound < inner.endIndex,
               inner[range.upperBound...].allSatisfy({ $0.isNumber })
            {
                inner = String(inner[..<range.lowerBound])
            }
            if let index = functionIndexByNameArity["\(inner)/\(argumentCount)"] {
                return .direct(index)
            }
        }
        return .stub(name)
    }

    /// Stdlib shims whose symbol doesn't survive lowering (the
    /// `<fn>$default` forwarders the default-argument expansion emits).
    /// Forwarder args are `[receiver, all-declared-params…, mask]` — the
    /// defaulted slots carry their real default values, so the helpers can
    /// ignore the trailing mask.
    private func stdlibShimName(for name: String, argumentTypes: [TypeID?]) -> String? {
        func isChar(_ index: Int) -> Bool {
            guard index < argumentTypes.count, let t = argumentTypes[index],
                  let types, case .primitive(.char, _) = types.kind(of: t)
            else { return false }
            return true
        }
        switch name {
        case "joinToString", "joinToString$default":
            // The full public shape carries (sep, prefix, postfix, limit,
            // truncated, transform[, mask]) after the receiver — 7+ args.
            // The private extern bridge is the 4-arg (sep, prefix, postfix)
            // form.
            return argumentTypes.count >= 7
                ? "__kk_wasm_join_to_string_full"
                : "__kk_string_joinToString"
        // kotlin.text forwarders.
        case "indexOf$default":
            return isChar(1)
                ? "__kk_wasm_string_index_of_char"
                : "__kk_wasm_string_index_of"
        case "lastIndexOf$default":
            // (s, needle, ic, mask) = no-start shape; (s, needle, start, ic,
            // mask) = start shape.
            let start = argumentTypes.count >= 5
            switch (start, isChar(1)) {
            case (false, false): return "__kk_wasm_string_last_index_of_nostart"
            case (false, true): return "__kk_wasm_string_last_index_of_char_nostart"
            case (true, false): return "__kk_wasm_string_last_index_of"
            case (true, true): return "__kk_wasm_string_last_index_of_char"
            }
        case "contains$default":
            return isChar(1)
                ? "__kk_wasm_string_contains_char_ic"
                : "__kk_wasm_string_contains_ic"
        case "startsWith$default":
            // argc 4 → (s, prefix, ic, mask); argc 5 → (s, prefix, start,
            // ic, mask).
            if argumentTypes.count >= 5 {
                return "__kk_wasm_string_starts_with_at"
            }
            return isChar(1)
                ? "__kk_wasm_string_starts_with_char"
                : "__kk_wasm_string_starts_with"
        case "endsWith$default":
            return isChar(1)
                ? "__kk_wasm_string_ends_with_char"
                : "__kk_wasm_string_ends_with"
        case "replace$default":
            return isChar(1)
                ? "__kk_wasm_string_replace_char"
                : "__kk_wasm_string_replace"
        case "replaceFirst$default":
            return isChar(1)
                ? "__kk_wasm_string_replace_first_char"
                : "__kk_wasm_string_replace_first"
        case "split$default":
            return "__kk_wasm_string_split"
        case "repeat$default":
            return "__kk_wasm_string_repeat"
        case "substring$default":
            return "__kk_wasm_string_substring_to"
        case "substringAfter$default":
            return isChar(1)
                ? "__kk_wasm_string_substring_after_char"
                : "__kk_wasm_string_substring_after"
        case "substringBefore$default":
            return isChar(1)
                ? "__kk_wasm_string_substring_before_char"
                : "__kk_wasm_string_substring_before"
        case "substringAfterLast$default":
            return isChar(1)
                ? "__kk_wasm_string_substring_after_last_char"
                : "__kk_wasm_string_substring_after_last"
        case "substringBeforeLast$default":
            return isChar(1)
                ? "__kk_wasm_string_substring_before_last_char"
                : "__kk_wasm_string_substring_before_last"
        case "capitalize$default":
            return "__kk_wasm_string_capitalize"
        case "decapitalize$default":
            return "__kk_wasm_string_decapitalize"
        default:
            return nil
        }
    }

    /// Maps stdlib symbols whose kklib bodies aren't in this module onto wasm
    /// runtime helpers that reproduce the same observable behavior.
    private func stdlibIntrinsicName(symbol: SymbolID?, argumentCount: Int) -> String? {
        // `call get`/`call set` carry synthetic *accessor* symbols that are not
        // in the plain symbol table — decode them to the backing property so
        // `arr.size` reaches the same fqName `Throwable.suppressed` uses.
        let resolvedSymbol = symbol.flatMap { sym -> SymbolID? in
            if symbols?.symbol(sym) != nil { return sym }
            return symbols?.propertySymbol(forAccessor: sym)
                ?? symbols?.accessorOwnerProperty(for: sym)
        }
        guard let resolvedSymbol, let sem = symbols?.symbol(resolvedSymbol) else {
            return nil
        }
        let symbol = resolvedSymbol
        // Accessor/intrinsic declarations carry their runtime symbol through
        // @KsSymbolName — if it matches an emitted helper, route directly.
        if let link = symbols?.externalLinkName(for: symbol),
           !link.isEmpty,
           WasmRuntimeHelpers.isEmittedHelperName(link)
        {
            return link
        }
        let fq = sem.fqName.map { interner.resolve($0) }
        if ProcessInfo.processInfo.environment["KSWIFTK_WASM_TRACE_CALLEES"] != nil {
            FileHandle.standardError.write(
                "wasm-callee /\(argumentCount) fq=\(fq.joined(separator: ".")) link=\(symbols?.externalLinkName(for: symbol) ?? "-")\n".data(using: .utf8)!
            )
        }
        // Throwable members whose bodies live in the kklib map onto the
        // intrinsic accessors backing the boxed storage. Accessor symbols
        // append a `$get`/`$set` component to the property's fqName.
        if fq.count >= 2, fq[0] == "kotlin" {
            var components = fq
            if components.last == "$get" || components.last == "$set" {
                components.removeLast()
            }
            let member = (components.last ?? "")
                .replacingOccurrences(of: ".$get", with: "")
                .replacingOccurrences(of: ".$set", with: "")
            if components.count >= 2, components[1] == "Throwable" {
                switch member {
                case "suppressed":
                    return "__kk_throwable_suppressedRaw"
                case "getStackTrace":
                    return "__kk_throwable_rawStackFrames"
                default: break
                }
            }
            if components.count == 3, components[1] == "Array",
               member == "size", argumentCount == 1
            {
                return "__kk_array_size"
            }
            // `Pair.first` carries @KsSymbolName on the property; `second`
            // and the componentN operators only mark their private
            // component accessors — route them onto the same slot readers.
            if components.count == 3, components[1] == "Pair" {
                switch member {
                case "first", "component1": return "__kk_pair_first"
                case "second", "component2": return "__kk_pair_second"
                case "toString": return "__kk_wasm_pair_to_string"
                default: break
                }
            }
            // `toString` members/extensions map to the matching renderer —
            // the kklib bodies aren't in this module.
            if member == "toString" {
                switch components.count >= 2 ? components[1] : "" {
                case "ranges":
                    return "__kk_wasm_range_to_string"
                case "Any":
                    return "kk_any_to_string"
                case "collections":
                    if components.count >= 4,
                       components[2] == "Map" || components[2] == "MutableMap"
                    {
                        return "__kk_wasm_entry_to_string"
                    }
                    if components.count >= 3 {
                        switch components[2] {
                        case "IndexedValue":
                            return "__kk_wasm_indexed_value_to_string"
                        case "LinkedHashMap", "HashMap", "Map", "MutableMap",
                             "AbstractMap":
                            return "__kk_wasm_map_to_string"
                        case "LinkedHashSet", "HashSet", "Set", "MutableSet",
                             "List", "MutableList", "ArrayList",
                             "AbstractList", "AbstractCollection", "Collection",
                             "Iterable", "MutableIterable":
                            return "__kk_wasm_list_to_string"
                        default: break
                        }
                    }
                default:
                    break
                }
            }
            if components.count >= 2, components[1] == "IndexedValue",
               member == "toString"
            {
                return "__kk_wasm_indexed_value_to_string"
            }
            // `IndexedValue.index`/`value`/`componentN` share the pair layout.
            if components.count >= 3, components[1] == "collections",
               components[2] == "IndexedValue"
            {
                switch member {
                case "index", "component1": return "__kk_pair_first"
                case "value", "component2": return "__kk_pair_second"
                default: break
                }
            }
            // `Map.Entry.key`/`value`/`componentN` and
            // `MutableMap.MutableEntry.setValue` share the pair slots (the
            // live-view second resolves through `__kk_pair_second`).
            if components.count >= 4, components[1] == "collections",
               (components[2] == "Map" && components[3] == "Entry")
                   || (components[2] == "MutableMap"
                       && components[3] == "MutableEntry")
            {
                switch member {
                case "key", "component1": return "__kk_pair_first"
                case "value", "component2": return "__kk_pair_second"
                case "setValue": return "__kk_mutable_map_entry_setValue"
                default: break
                }
            }
            // `IntArray.size`/`Array<T>.size`/... are top-level extension
            // properties in package `kotlin.collections` — their accessor
            // fqName is `kotlin.collections.size.$get` with no receiver
            // component. Every bundled `kotlin.collections.size` getter
            // forwards to an array-meta load.
            if components == ["kotlin", "collections", "size"], argumentCount == 1 {
                return "__kk_array_size"
            }
            // `String.length` is a `kotlin`-package property in the bundled
            // stdlib — its accessor decodes to `kotlin.length.$get`.
            if components == ["kotlin", "length"], argumentCount == 1 {
                return "kk_string_length"
            }
            if components.count == 2 {
                switch components[1] {
                case "addSuppressed": return "__kk_throwable_appendSuppressed"
                case "getSuppressed": return "__kk_throwable_suppressedRaw"
                case "suppressedExceptions": return "__kk_throwable_suppressed_list"
                case "initCause": return "__kk_throwable_setCause"
                case "error": return "__kk_wasm_error"
                case "TODO": return "__kk_wasm_todo"
                default: break
                }
            }
            // `kotlin.comparisons` — ordering helpers whose kklib bodies
            // inline-expand to these leaf calls.
            if components.count == 3, components[1] == "comparisons" {
                switch member {
                case "compareValues", "compareNullable",
                     "compareValuesUnchecked":
                    return "__kk_wasm_compare_values"
                case "naturalOrder":
                    return "__kk_wasm_natural_order"
                case "reverseOrder":
                    return "__kk_wasm_reverse_order"
                case "minOf":
                    return argumentCount == 2 ? "__kk_wasm_min_of" : nil
                case "maxOf":
                    return argumentCount == 2 ? "__kk_wasm_max_of" : nil
                default: break
                }
            }
            // `kotlin.ranges` member/extension calls whose kklib bodies can't
            // run forward onto the range-box helpers — every nominal tag
            // shares the `{first@16, last@24, step@32}` layout.
            if components.count >= 2, components[1] == "ranges" {
                switch member {
                case "until": return "__kk_op_rangeUntil"
                case "downTo": return "__kk_op_downTo"
                case "step": return "__kk_op_step"
                case "rangeTo": return "__kk_op_rangeTo"
                case "toList": return "__kk_range_to_list"
                case "contains": return "__kk_range_contains"
                case "isEmpty": return "__kk_range_isEmpty"
                case "first", "start": return "__kk_range_first"
                case "last", "endInclusive": return "__kk_range_last"
                case "iterator": return "__kk_range_for_in_iterator"
                default: break
                }
            }
            // `kotlin.collections` member/extension calls on the shared
            // `{array,count,flags}` box. Owner guard keeps Map-box members
            // (`isEmpty`, `contains`…) from reading the wrong slot layout;
            // extension fns have no owner component (nil = allowed).
            if components.count >= 3, components[1] == "collections" {
                let listBoxOwners: Set<String> = [
                    "Iterable", "MutableIterable", "Collection",
                    "MutableCollection", "List", "MutableList", "ArrayList",
                    "AbstractList", "AbstractCollection", "Set", "MutableSet",
                    "HashSet", "LinkedHashSet",
                ]
                if components.count == 3 || listBoxOwners.contains(components[2]) {
                    // `sum`/`sorted` disambiguate Int/Double receivers and
                    // primitive-array receivers through the signature.
                    func elementIsFp(_ sig: FunctionSignature?) -> Bool {
                        guard let t = sig?.receiverType, let types,
                              case let .classType(ct) = types.kind(of: t),
                              let arg = ct.args.first
                        else { return false }
                        let argType: TypeID
                        switch arg {
                        case let .invariant(id), let .out(id), let .in(id):
                            argType = id
                        case .star:
                            return false
                        }
                        guard case .primitive(.double, _) = types.kind(of: argType)
                        else { return false }
                        return true
                    }
                    func receiverIsPrimArray(
                        _ sig: FunctionSignature?, names: Set<String>
                    ) -> Bool {
                        primReceiverName(sig).map { names.contains($0) } ?? false
                    }
                    func primReceiverName(_ sig: FunctionSignature?) -> String? {
                        guard let t = sig?.receiverType, let types,
                              case let .classType(ct) = types.kind(of: t),
                              let sym = symbols?.symbol(ct.classSymbol),
                              let last = sym.fqName.last
                        else { return nil }
                        return interner.resolve(last)
                    }
                    // `*Array.toList` extern helpers keyed by the receiver's
                    // simple name (`Array` covers the generic object array).
                    let arrayToListHelpers: [String: String] = [
                        "IntArray": "__kk_intArray_toList",
                        "LongArray": "__kk_longArray_toList",
                        "ShortArray": "__kk_shortArray_toList",
                        "ByteArray": "__kk_byteArray_toList",
                        "CharArray": "__kk_charArray_toList",
                        "BooleanArray": "__kk_booleanArray_toList",
                        "UIntArray": "__kk_uIntArray_toList",
                        "ULongArray": "__kk_uLongArray_toList",
                        "DoubleArray": "__kk_doubleArray_toList",
                        "FloatArray": "__kk_floatArray_toList",
                        "UByteArray": "__kk_uByteArray_toList",
                        "UShortArray": "__kk_uShortArray_toList",
                        "Array": "__kk_array_toList",
                    ]
                    let sig = symbols?.functionSignature(for: symbol)
                    switch member {
                    case "indexOf": return "__kk_list_index_of"
                    case "lastIndexOf": return "__kk_list_last_index_of"
                    case "contains": return "__kk_set_contains"
                    case "first":
                        return argumentCount == 1 ? "__kk_wasm_iterable_first" : nil
                    case "firstOrNull":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_first_or_null" : nil
                    case "last":
                        return argumentCount == 1 ? "__kk_wasm_iterable_last" : nil
                    case "lastOrNull":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_last_or_null" : nil
                    case "single":
                        return argumentCount == 1 ? "__kk_wasm_iterable_single" : nil
                    case "singleOrNull":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_single_or_null" : nil
                    case "elementAt":
                        return "__kk_wasm_iterable_element_at"
                    case "elementAtOrNull":
                        return "__kk_wasm_iterable_element_at_or_null"
                    case "isEmpty": return "__kk_list_is_empty"
                    case "count":
                        return argumentCount == 1 ? "__kk_wasm_iterable_count" : nil
                    case "min":
                        return argumentCount == 1 ? "__kk_wasm_iterable_min" : nil
                    case "max":
                        return argumentCount == 1 ? "__kk_wasm_iterable_max" : nil
                    case "minOrNull":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_min_or_null" : nil
                    case "maxOrNull":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_max_or_null" : nil
                    case "joinToString":
                        return argumentCount >= 7
                            ? "__kk_wasm_join_to_string_full"
                            : "__kk_string_joinToString"
                    case "toList":
                        if let recv = primReceiverName(sig),
                           let helper = arrayToListHelpers[recv] {
                            return helper
                        }
                        return argumentCount == 1 ? "__kk_list_to_list" : nil
                    case "toMutableList":
                        if primReceiverName(sig) != nil {
                            return "__kk_wasm_prim_array_to_mutable_list"
                        }
                        return "__kk_wasm_iterable_to_mutable_list"
                    case "copyOf":
                        if argumentCount == 1, primReceiverName(sig) != nil {
                            return "__kk_wasm_prim_array_copy"
                        }
                        return nil
                    case "toMutableSet":
                        return "__kk_wasm_iterable_to_mutable_set"
                    case "toHashSet":
                        return "__kk_wasm_iterable_to_hash_set"
                    case "toSet":
                        return "__kk_wasm_iterable_to_set"
                    case "take":
                        return "__kk_wasm_iterable_take"
                    case "drop":
                        return "__kk_wasm_iterable_drop"
                    case "reversed":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_reversed" : nil
                    case "distinct":
                        return "__kk_wasm_iterable_distinct"
                    case "flatten":
                        return "__kk_wasm_iterable_flatten"
                    case "filterNotNull":
                        return "__kk_wasm_iterable_filter_not_null"
                    case "zipWithNext":
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_zip_with_next" : nil
                    case "withIndex":
                        return "__kk_wasm_iterable_with_index"
                    case "unzip":
                        return "__kk_wasm_iterable_unzip"
                    case "chunked":
                        return "__kk_wasm_iterable_chunked"
                    case "zip":
                        return argumentCount == 2 ? "__kk_wasm_iterable_zip" : nil
                    case "sorted":
                        if receiverIsPrimArray(sig, names: [
                            "IntArray", "LongArray", "ShortArray",
                            "ByteArray", "CharArray", "BooleanArray",
                        ]) {
                            return "__kk_wasm_int_array_sorted"
                        }
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_sorted" : nil
                    case "sortedDescending":
                        if receiverIsPrimArray(sig, names: [
                            "IntArray", "LongArray", "ShortArray",
                            "ByteArray", "CharArray", "BooleanArray",
                        ]) {
                            return "__kk_wasm_int_array_sorted_desc"
                        }
                        return argumentCount == 1
                            ? "__kk_wasm_iterable_sorted_desc" : nil
                    case "sortedWith":
                        return "__kk_wasm_iterable_sorted_with"
                    case "sortedBy":
                        return "__kk_wasm_iterable_sorted_by"
                    case "sortedByDescending":
                        return "__kk_wasm_iterable_sorted_by_desc"
                    case "sum":
                        if receiverIsPrimArray(
                            sig, names: ["DoubleArray", "FloatArray"]
                        ) {
                            return "__kk_wasm_prim_array_sum_fp"
                        }
                        if receiverIsPrimArray(sig, names: [
                            "IntArray", "LongArray", "ShortArray", "ByteArray",
                        ]) {
                            return "__kk_wasm_prim_array_sum_int"
                        }
                        return elementIsFp(sig)
                            ? "__kk_wasm_iterable_sum_fp"
                            : "__kk_wasm_iterable_sum_int"
                    default: break
                    }
                }
            }
            // `List`/`MutableList`/`ArrayList` member `size` accessors decode
            // to `kotlin.collections.<Owner>.size`; all read the same slot.
            if components.count == 4,
               components[0] == "kotlin", components[1] == "collections",
               member == "size", argumentCount == 1,
               ["List", "MutableList", "ArrayList", "Collection",
                "MutableCollection", "AbstractList", "AbstractCollection",
                "Iterable"].contains(components[2])
            {
                return "__kk_list_size"
            }
            // `kotlin.text` String/Char ops whose kklib bodies aren't in
            // this module — the flat-string helpers reproduce the same
            // byte-level behavior. Overloads sharing fqName+arity (Char vs
            // String receivers/params) are split on the resolved signature.
            if components.count == 3, components[1] == "text" {
                let sig = symbols?.functionSignature(for: symbol)
                let sigParamCount = sig?.parameterTypes.count ?? -1
                func isCharParam(_ index: Int) -> Bool {
                    guard let sig, index < sig.parameterTypes.count,
                          let types,
                          case .primitive(.char, _) = types.kind(of: sig.parameterTypes[index])
                    else { return false }
                    return true
                }
                let receiverIsChar: Bool = {
                    guard let t = sig?.receiverType, let types else { return false }
                    if case .primitive(.char, _) = types.kind(of: t) { return true }
                    return false
                }()
                switch member {
                case "uppercase", "toUpperCase", "titlecase":
                    return receiverIsChar
                        ? "__kk_wasm_char_upper_str"
                        : "__kk_wasm_string_upper"
                case "lowercase", "toLowerCase":
                    return receiverIsChar
                        ? "__kk_wasm_char_lower_str"
                        : "__kk_wasm_string_lower"
                case "uppercaseChar", "titlecaseChar", "toTitleCase":
                    return "__kk_wasm_char_upper"
                case "lowercaseChar":
                    return "__kk_wasm_char_lower"
                case "capitalize":
                    return "__kk_wasm_string_capitalize"
                case "decapitalize":
                    return "__kk_wasm_string_decapitalize"
                case "substring", "subSequence":
                    return argumentCount == 2
                        ? "__kk_wasm_string_substring"
                        : "__kk_wasm_string_substring_to"
                case "trim":
                    return argumentCount == 1 ? "__kk_wasm_string_trim" : nil
                case "trimStart":
                    return argumentCount == 1 ? "__kk_wasm_string_trim_start" : nil
                case "trimEnd":
                    return argumentCount == 1 ? "__kk_wasm_string_trim_end" : nil
                case "repeat":
                    return argumentCount == 2 ? "__kk_wasm_string_repeat" : nil
                case "reversed":
                    return argumentCount == 1 ? "__kk_wasm_string_reversed" : nil
                case "isEmpty":
                    return argumentCount == 1 ? "__kk_wasm_string_is_empty" : nil
                case "isNotEmpty":
                    return argumentCount == 1 ? "__kk_wasm_string_is_not_empty" : nil
                case "isBlank":
                    return argumentCount == 1 ? "__kk_wasm_string_is_blank" : nil
                case "isNotBlank":
                    return argumentCount == 1 ? "__kk_wasm_string_is_not_blank" : nil
                case "contains":
                    let char = isCharParam(0)
                    if argumentCount == 2 {
                        return char
                            ? "__kk_wasm_string_contains_char"
                            : "__kk_wasm_string_contains"
                    }
                    return char
                        ? "__kk_wasm_string_contains_char_ic"
                        : "__kk_wasm_string_contains_ic"
                case "indexOf":
                    return isCharParam(0)
                        ? "__kk_wasm_string_index_of_char"
                        : "__kk_wasm_string_index_of"
                case "lastIndexOf":
                    let hasStart = sigParamCount >= 3
                        || (sigParamCount < 0 && argumentCount >= 4)
                    switch (hasStart, isCharParam(0)) {
                    case (false, false): return "__kk_wasm_string_last_index_of_nostart"
                    case (false, true): return "__kk_wasm_string_last_index_of_char_nostart"
                    case (true, false): return "__kk_wasm_string_last_index_of"
                    case (true, true): return "__kk_wasm_string_last_index_of_char"
                    }
                case "startsWith":
                    let hasStart = sigParamCount >= 3
                        || (sigParamCount < 0 && argumentCount >= 4)
                    if hasStart { return "__kk_wasm_string_starts_with_at" }
                    return isCharParam(0)
                        ? "__kk_wasm_string_starts_with_char"
                        : "__kk_wasm_string_starts_with"
                case "endsWith":
                    return isCharParam(0)
                        ? "__kk_wasm_string_ends_with_char"
                        : "__kk_wasm_string_ends_with"
                case "replace":
                    return isCharParam(0)
                        ? "__kk_wasm_string_replace_char"
                        : "__kk_wasm_string_replace"
                case "replaceFirst":
                    return isCharParam(0)
                        ? "__kk_wasm_string_replace_first_char"
                        : "__kk_wasm_string_replace_first"
                case "split":
                    // Only single-String-delimiter shapes map to the byte
                    // scan; vararg/Regex overloads keep their own bodies.
                    if sig?.valueParameterIsVararg.first == true { break }
                    return "__kk_wasm_string_split"
                case "get", "charAt":
                    return "kk_string_get"
                case "toInt":
                    return "__kk_wasm_string_to_int"
                case "toLong":
                    return "__kk_wasm_string_to_long"
                case "toIntOrNull":
                    return "__kk_wasm_string_to_int_or_null"
                case "toLongOrNull":
                    return "__kk_wasm_string_to_long_or_null"
                case "toBoolean":
                    return "__kk_wasm_string_to_boolean"
                case "toDouble":
                    return "__kk_wasm_string_to_double"
                case "toFloat":
                    return "__kk_wasm_string_to_float"
                case "toDoubleOrNull":
                    return "__kk_wasm_string_to_double_or_null"
                case "toFloatOrNull":
                    return "__kk_wasm_string_to_float_or_null"
                case "substringAfter":
                    return isCharParam(0)
                        ? "__kk_wasm_string_substring_after_char"
                        : "__kk_wasm_string_substring_after"
                case "substringBefore":
                    return isCharParam(0)
                        ? "__kk_wasm_string_substring_before_char"
                        : "__kk_wasm_string_substring_before"
                case "substringAfterLast":
                    return isCharParam(0)
                        ? "__kk_wasm_string_substring_after_last_char"
                        : "__kk_wasm_string_substring_after_last"
                case "substringBeforeLast":
                    return isCharParam(0)
                        ? "__kk_wasm_string_substring_before_last_char"
                        : "__kk_wasm_string_substring_before_last"
                case "removePrefix":
                    return "__kk_wasm_string_remove_prefix"
                case "removeSuffix":
                    return "__kk_wasm_string_remove_suffix"
                case "padStart":
                    return argumentCount >= 3 ? "__kk_wasm_string_pad_start" : nil
                case "padEnd":
                    return argumentCount >= 3 ? "__kk_wasm_string_pad_end" : nil
                case "lines":
                    return "__kk_wasm_string_lines"
                default: break
                }
            }
            guard fq.count == 3, fq[1] == "io" else {
                return nil
            }
            // `println(Any?)` must stringify through the Any path — the raw
            // writer reads a string layout and mangles heap objects.
            let isStringParam: Bool = {
                guard let sig = symbols?.functionSignature(for: symbol),
                      let p = sig.parameterTypes.first, let types,
                      case .stringStruct = types.kind(of: p)
                else { return false }
                return true
            }()
            switch fq[2] {
            case "println":
                if argumentCount == 0 { return "__kk_wasm_println_empty" }
                return isStringParam ? "__kk_println_raw" : "__kk_println_any"
            case "print":
                if argumentCount == 0 { return "__kk_wasm_noop" }
                return isStringParam ? "__kk_print_raw" : "__kk_print_any"
            default: return nil
            }
        }
        return nil
    }

    enum CalleeResolution {
        case direct(Int)
        case emittedHelper(Int)
        case stub(String)
    }

    func wasmImportFDWrite() -> Int {
        if fdWriteImport < 0 {
            fdWriteImport = module.addImportFunction(
                module: "wasi_snapshot_preview1",
                name: "fd_write",
                type: WasmFuncType(params: [.i32, .i32, .i32, .i32], results: [.i32])
            )
        }
        return fdWriteImport
    }

    func wasmImportProcExit() -> Int {
        if procExitImport < 0 {
            procExitImport = module.addImportFunction(
                module: "wasi_snapshot_preview1",
                name: "proc_exit",
                type: WasmFuncType(params: [.i32], results: [])
            )
        }
        return procExitImport
    }

    /// Places `bytes` in a data segment and returns its linear-memory offset.
    /// Used by helpers that need compile-time-known payloads (e.g. the
    /// "true"/"false" spellings inside `kk_any_to_string`).
    func dataOffset(for bytes: [UInt8]) -> Int64 {
        let offset = dataCursor
        dataCursor += Int64(bytes.count)
        module.addDataSegment(offset: offset, bytes: bytes)
        return offset
    }

    /// Lazily emits (or returns) the wasm function implementing a runtime
    /// helper callable by KIR name (`kk_object_new`, `__kk_println_raw`, ...).
    /// `(helper, arity)` backing a stdlib member whose body never
    /// materialized as a module function. Vtable/itable registrations carry
    /// the implementation as a `symbolRef`; without this mapping the slot
    /// would hold the raw symbol ID and `call_indirect` would read a wild
    /// table index (`linkedSetOf(1,2) == setOf(2,1)` crashes on
    /// `AbstractMutableSet.equals`). Members land on the same helpers the
    /// sentinel boxes use, so e.g. `AbstractMutableSet.equals` reaches the
    /// structural set compare the JVM's `AbstractSet.equals` specifies.
    func memberThunkInfo(for symbol: SymbolID) -> (helper: String, arity: Int)? {
        guard let symbols else { return nil }
        var lookup = symbol
        if let owner = symbols.accessorOwnerProperty(for: symbol)
            ?? SyntheticSymbolScheme.propertyOwnerOfGetterAccessor(symbol) {
            lookup = owner
        } else if SyntheticSymbolScheme.isLikelySyntheticSetterAccessor(symbol) {
            let owner = SyntheticSymbolScheme.originalPropertySymbolFromSetterAccessor(symbol)
            if owner.rawValue >= 0 { lookup = owner }
        }
        guard let sem = symbols.symbol(lookup) else { return nil }
        let fq = sem.fqName.map { interner.resolve($0) }
        guard fq.count >= 3, fq[0] == "kotlin" else { return nil }
        let member = fq[fq.count - 1]
        let owner = fq[fq.count - 2]
        let grandparent = fq.count >= 3 ? fq[fq.count - 3] : ""

        let setOwners: Set<String> = [
            "Set", "MutableSet", "AbstractSet", "AbstractMutableSet",
            "HashSet", "LinkedHashSet",
        ]
        let listOwners: Set<String> = [
            "List", "MutableList", "AbstractList", "AbstractMutableList",
            "ArrayList", "LinkedList",
        ]
        let collectionOwners: Set<String> = [
            "Collection", "MutableCollection", "AbstractCollection",
            "AbstractMutableCollection", "Iterable", "MutableIterable",
        ]
        let mapOwners: Set<String> = [
            "Map", "MutableMap", "AbstractMap", "AbstractMutableMap",
            "HashMap", "LinkedHashMap",
        ]
        let isSet = setOwners.contains(owner)
        let isList = listOwners.contains(owner)
        let isGenericColl = collectionOwners.contains(owner)
        let isMap = mapOwners.contains(owner)
        let isEntry = owner == "Entry" && grandparent == "Map"
            || owner == "MutableEntry" && grandparent == "MutableMap"
        let anyColl = isSet || isList || isGenericColl || isMap

        let thunk: (helper: String, arity: Int)?
        switch member {
        case "equals":
            if anyColl { thunk = ("__kk_wasm_elem_eq", 2) }
            else if owner == "Any" { thunk = ("__kk_wasm_identity_eq", 2) }
            else { thunk = nil }
        case "hashCode":
            if anyColl { thunk = ("__kk_wasm_collection_hash", 1) }
            else if owner == "Any" { thunk = ("__kk_wasm_identity_hash", 1) }
            else { thunk = nil }
        case "toString":
            thunk = anyColl || isEntry || owner == "Any"
                ? ("__kk_wasm_obj_to_string", 1) : nil
        case "iterator":
            thunk = isSet || isList || isGenericColl
                ? ("kk_iterable_iterator", 1) : nil
        case "size":
            thunk = isSet || isList || isGenericColl ? ("__kk_set_size", 1)
                : isMap ? ("__kk_map_size", 1) : nil
        case "isEmpty":
            thunk = isSet || isList || isGenericColl ? ("__kk_set_is_empty", 1)
                : isMap ? ("__kk_map_is_empty", 1) : nil
        case "contains":
            thunk = isSet || isList || isGenericColl
                ? ("__kk_set_contains", 2) : nil
        case "containsAll":
            thunk = isSet || isList || isGenericColl
                ? ("__kk_wasm_contains_all", 2) : nil
        case "containsKey":
            thunk = isMap ? ("__kk_map_contains_key", 2) : nil
        case "containsValue":
            thunk = isMap ? ("__kk_map_contains_value", 2) : nil
        case "keys":
            thunk = isMap ? ("__kk_map_keys", 1) : nil
        case "values":
            thunk = isMap ? ("__kk_map_values", 1) : nil
        case "entries":
            thunk = isMap ? ("__kk_map_entries", 1) : nil
        case "get":
            thunk = isMap ? ("__kk_map_get", 2)
                : isList ? ("__kk_list_get", 2) : nil
        case "put":
            thunk = isMap ? ("__kk_mutable_map_put", 3) : nil
        case "remove":
            thunk = isSet ? ("__kk_mutable_set_remove", 2)
                : isMap ? ("__kk_mutable_map_remove", 2) : nil
        case "clear":
            thunk = isSet || isList || isGenericColl
                ? ("__kk_mutable_set_clear", 1)
                : isMap ? ("__kk_mutable_map_clear", 1) : nil
        case "add":
            thunk = isSet ? ("__kk_mutable_set_add", 2)
                : isList ? ("__kk_mutable_list_add", 2) : nil
        case "subList":
            thunk = isList ? ("kk_list_subList", 3) : nil
        case "indexOf":
            thunk = isList ? ("__kk_list_index_of", 2) : nil
        case "lastIndexOf":
            thunk = isList ? ("__kk_list_last_index_of", 2) : nil
        case "key":
            thunk = isEntry ? ("__kk_pair_first", 1) : nil
        case "value":
            thunk = isEntry ? ("__kk_pair_second", 1) : nil
        case "setValue":
            thunk = isEntry ? ("__kk_mutable_map_entry_setValue", 2) : nil
        case "component1":
            thunk = isEntry ? ("__kk_pair_first", 1) : nil
        case "component2":
            thunk = isEntry ? ("__kk_pair_second", 1) : nil
        default:
            thunk = nil
        }
        guard let thunk else { return nil }
        // The vtable caller invokes the slot with `i64Signature(1+params)`;
        // only serve members whose signature arity matches the thunk.
        if let signature = symbols.functionSignature(for: lookup),
           signature.parameterTypes.count + 1 != thunk.arity
        {
            return nil
        }
        return thunk
    }

    func emittedHelperIndex(for name: String, argumentCount: Int) -> Int {
        let key = "\(name)/\(argumentCount)"
        if let existing = helperIndexByName[key] { return existing }
        guard WasmRuntimeHelpers.isEmittedHelperName(name) else {
            return stubIndex(for: name, argumentCount: argumentCount)
        }
        // Pre-register the function index so helpers that call each other
        // transitively (e.g. `kk_any_to_string` → collection renderers →
        // `kk_any_to_string`) resolve the cycle instead of recursing.
        let index = module.addFunction(
            type: .i64Signature(argumentCount),
            name: "$\(name)"
        )
        helperIndexByName[key] = index
        if let body = WasmRuntimeHelpers.emittedBody(
            for: name,
            argumentCount: argumentCount,
            context: self
        ) {
            module.setBody(body, forFunctionIndex: index)
        } else {
            // Name is registered but this arity has no body — emit a
            // return-0 body so the pre-allocated function stays valid.
            var body = WasmCode()
            body.u(0)
            body.i64Const(0)
            body.op(WasmOpcode.end)
            module.setBody(body.bytes, forFunctionIndex: index)
        }
        return index
    }

    func stubIndex(for name: String, argumentCount: Int) -> Int {
        let key = "\(name)/\(argumentCount)"
        if let existing = stubIndexByNameArity[key] { return existing }
        let index = module.addFunction(type: .i64Signature(argumentCount), name: "$stub_\(name)")
        stubIndexByNameArity[key] = index
        stubbedCallees.append(name)
        var code = WasmCode()
        code.i64Const(0)
        var body = WasmCode()
        body.u(0) // no extra locals
        body.bytes.append(contentsOf: code.bytes)
        body.op(WasmOpcode.end)
        module.setBody(body.bytes, forFunctionIndex: index)
        return index
    }
}

public struct WasmEmitter {
    public init() {}

    public func emitModule(
        module kir: KIRModule,
        interner: StringInterner,
        symbols: SymbolTable?,
        types: TypeSystem?,
        entrySymbol: SymbolID?,
        target: TargetTriple,
        diagnostics: DiagnosticEngine?
    ) throws -> WasmEmissionResult {
        let ctx = WasmModuleContext(
            kir: kir,
            interner: interner,
            symbols: symbols,
            types: types,
            isWASI: target.isWASI || (!target.isWasmJS && target.isWasm)
        )

        // Pre-register WASI imports so they occupy the leading function indices.
        if ctx.isWASI {
            _ = ctx.wasmImportFDWrite()
            _ = ctx.wasmImportProcExit()
        }

        // Reserve funcref table slot 0 for a dispatch-error thunk. Vtable and
        // itable memory is zero-initialised, so an unwritten slot reads back
        // as 0 — without a real occupant here `call_indirect` would alias
        // whatever function landed at slot 0 (the native equivalent is
        // `kk_dispatch_error`). Every genuine registration gets a slot >= 1.
        let dispatchErrorIndex = ctx.module.addFunction(
            type: .i64Signature(0), name: "$__kk_wasm_dispatch_error"
        )
        var dispatchErrorBody = WasmCode()
        dispatchErrorBody.u(0)
        dispatchErrorBody.op(WasmOpcode.unreachable)
        dispatchErrorBody.op(WasmOpcode.end)
        ctx.module.setBody(dispatchErrorBody.bytes, forFunctionIndex: dispatchErrorIndex)
        _ = ctx.module.tableSlot(forFunction: dispatchErrorIndex)

        // Register internal functions, then KIR globals, then runtime globals.
        let functions = ctx.emitFunctions()
        var ambiguous: Set<String> = []
        var aritySeen: Set<String> = []
        for function in functions {
            let index = ctx.module.addFunction(
                type: .i64Signature(function.params.count),
                name: interner.resolve(function.name)
            )
            ctx.functionIndexBySymbol[function.symbol] = index
            let name = interner.resolve(function.name)
            let key = "\(name)/\(function.params.count)"
            if aritySeen.contains(key) {
                ambiguous.insert(key)
            } else {
                aritySeen.insert(key)
                ctx.functionIndexByNameArity[key] = index
            }
            var paramLocals: [Int32: Int] = [:]
            for (index, param) in function.params.enumerated() {
                paramLocals[param.symbol.rawValue] = index
            }
            ctx.paramIndexBySymbolByFunction[function.symbol] = paramLocals
        }
        for key in ambiguous {
            ctx.functionIndexByNameArity.removeValue(forKey: key)
        }

        for decl in kir.arena.declarations {
            guard case let .global(global) = decl else { continue }
            ctx.globalIndexBySymbol[global.symbol] = ctx.module.addGlobal(
                initialValue: 0,
                name: "$g\(global.symbol.rawValue)"
            )
        }
        ctx.thrownGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_thrown")
        ctx.heapGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_heap")
        ctx.edgeHeadGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_type_edges")
        // Filled in after all bodies are emitted: the data segments grow as
        // string literals are discovered, so the heap base is only known then.
        ctx.dataEndGlobal = ctx.module.addGlobal(initialValue: 0, name: "$__kk_data_end")

        // Emit function bodies.
        var emissionErrors: [Error] = []
        for function in functions {
            do {
                let emission = WasmFunctionEmission(ctx: ctx, function: function)
                let body = try emission.emitBody()
                guard let index = ctx.functionIndexBySymbol[function.symbol] else { continue }
                ctx.module.setBody(body, forFunctionIndex: index)
            } catch {
                emissionErrors.append(error)
            }
        }
        if let first = emissionErrors.first {
            diagnostics?.error(
                "KSWIFTK-WASM-0003",
                "wasm emission failed: \(first)",
                range: nil
            )
            throw first
        }

        // Export user-visible functions and the entry wrapper.
        var exportedNames: Set<String> = []
        for function in functions {
            let rawName = ctx.symbols?.externalLinkName(for: function.symbol)
                ?? interner.resolve(function.name)
            let exportName = sanitizeExportName(rawName)
            guard !exportName.isEmpty, exportedNames.insert(exportName).inserted,
                  let index = ctx.functionIndexBySymbol[function.symbol] else { continue }
            ctx.module.addExport(name: exportName, kind: .function, index: index)
        }

        if let entrySymbol, let entryIndex = ctx.functionIndexBySymbol[entrySymbol] {
            emitEntryWrapper(ctx: ctx, entryIndex: entryIndex)
        }

        // Memory sizing: data segments are placed as they are discovered, so
        // the heap base is fixed now that all bodies are emitted. `$__kk_alloc`
        // lazily seeds the bump pointer from this global on first use, which
        // also covers direct calls to exported functions that skip `_start`.
        let dataEnd = align(ctx.dataCursor, to: 16)
        ctx.module.setGlobalInitialValue(index: ctx.dataEndGlobal, value: dataEnd)
        ctx.module.memoryMinPages = Int((dataEnd + 16 * 65_536) / 65_536)
        ctx.module.exportMemoryName = "memory"

        if !ctx.stubbedCallees.isEmpty {
            let dumpAll = ProcessInfo.processInfo.environment["KSWIFTK_WASM_ALL_STUBS"] != nil
            let preview = dumpAll
                ? ctx.stubbedCallees.sorted().joined(separator: ", ")
                : ctx.stubbedCallees.prefix(8).joined(separator: ", ")
            diagnostics?.warning(
                "KSWIFTK-WASM-0001",
                "\(ctx.stubbedCallees.count) runtime callee(s) have no wasm implementation yet and were stubbed to return 0: \(preview)\(ctx.stubbedCallees.count > 8 ? ", ..." : "")",
                range: nil
            )
        }
        for note in ctx.notes {
            diagnostics?.warning("KSWIFTK-WASM-0002", note, range: nil)
        }

        return WasmEmissionResult(
            bytes: ctx.module.encode(),
            stubbedCallees: ctx.stubbedCallees.sorted(),
            notes: ctx.notes
        )
    }

    /// `_start` (WASI) / `main` (wasm-js) calls the Kotlin entry, then converts
    /// a non-zero thrown channel into an stderr diagnostic + `proc_exit(70)`
    /// (WASI) or a trap (wasm-js). Mirrors Kotlin/Native's uncaught-throwable
    /// reporting (`Uncaught Kotlin exception: <toString>`).
    private func emitEntryWrapper(ctx: WasmModuleContext, entryIndex: Int) {
        var code = WasmCode()
        code.call(entryIndex)
        code.op(WasmOpcode.drop)
        code.globalGet(ctx.thrownGlobal)
        code.localSet(0)
        code.localGet(0)
        code.op(WasmOpcode.i64Eqz)
        code.openIf()
        // thrown == 0 → normal exit
        code.elseBranch()
        if ctx.isWASI {
            // stderr: "Uncaught Kotlin exception: " + toString(thrown) + "\n"
            let prefix = "Uncaught Kotlin exception: "
            let prefixOffset = ctx.dataOffset(for: Array(prefix.utf8))
            code.i64Const(prefixOffset)
            code.i64Const(Int64(prefix.utf8.count))
            code.call(ctx.emittedHelperIndex(
                for: "__kk_string_literal_from_utf8",
                argumentCount: 2
            ))
            code.call(ctx.emittedHelperIndex(for: "__kk_printStderr", argumentCount: 1))
            code.op(WasmOpcode.drop)
            code.localGet(0)
            code.call(ctx.emittedHelperIndex(for: "__kk_throwable_toString", argumentCount: 1))
            code.call(ctx.emittedHelperIndex(for: "$__kk_println_stderr", argumentCount: 1))
            code.op(WasmOpcode.drop)
            code.i32Const(70) // EX_SOFTWARE
            code.call(ctx.wasmImportProcExit())
        }
        code.op(WasmOpcode.unreachable)
        code.end()
        var body = WasmCode()
        body.u(1)
        body.u(1)
        body.op(WasmValType.i64.rawValue)
        body.bytes.append(contentsOf: code.bytes)
        body.op(WasmOpcode.end)
        let index = ctx.module.addFunction(
            type: WasmFuncType(params: [], results: []),
            name: "$__kk_wasm_start"
        )
        ctx.module.setBody(body.bytes, forFunctionIndex: index)
        ctx.module.addExport(
            name: ctx.isWASI ? "_start" : "main",
            kind: .function,
            index: index
        )
    }

    private func sanitizeExportName(_ name: String) -> String {
        var out = ""
        for character in name {
            if character.isLetter || character.isNumber || character == "_" || character == "$" {
                out.append(character)
            } else {
                out.append("_")
            }
        }
        return out
    }

    private func align(_ value: Int64, to alignment: Int64) -> Int64 {
        (value + alignment - 1) / alignment * alignment
    }
}
