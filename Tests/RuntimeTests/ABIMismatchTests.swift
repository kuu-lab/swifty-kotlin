import RuntimeABI
import Testing

/// Historical identities for removed-symbol assertions and family exclusions.
/// These stay independent of the current spec so resurrected exports are detected.
enum RuntimeABISpecTestSymbol: Hashable, CustomStringConvertible {
    enum Family: String {
        case array
        case callableRef = "callable_ref"
        case char
        case indexedValue = "indexed_value"
        case iterable
        case kfunction
        case kpropertyStub = "kproperty_stub"
        case list
        case locale
        case long
        case mutableCollection = "mutable_collection"
        case regex
        case string
        case ubyte
        case uint
        case ulong
        case ushort
    }

    enum Namespace {
        case runtime, bridge

        fileprivate func stem(in name: String) -> String? {
            let components = name.split(separator: "_", omittingEmptySubsequences: false)
            let prefix: [Substring] = switch self {
            case .runtime: ["kk"]
            case .bridge: ["", "", "kk"]
            }
            guard components.starts(with: prefix) else { return nil }
            return components.dropFirst(prefix.count).joined(separator: "_")
        }
    }

    case runtime(Family, String)
    case bridge(Family, String)

    private var identity: (namespace: Namespace, family: Family, member: String) {
        switch self {
        case let .runtime(family, member): (.runtime, family, member)
        case let .bridge(family, member): (.bridge, family, member)
        }
    }

    var description: String {
        let (namespace, family, member) = identity
        return "\(namespace).\(family).\(member)"
    }

    func matches(_ name: String) -> Bool {
        let (namespace, family, member) = identity
        let stem = family.rawValue + "_" + member
        return namespace.stem(in: name) == stem
    }

    static func matchesFamily(_ family: Family, namespace: Namespace, name: String) -> Bool {
        namespace.stem(in: name)?.hasPrefix(family.rawValue + "_") == true
    }
}

extension RuntimeABIFunctionSpec {
    /// Require canonical records to remain uniquely registered in the inventory.
    func requireRegistration() throws -> Self {
        let registered = RuntimeABISpec.allFunctions.filter { $0.name == name }
        try #require(registered.count == 1, "Expected one RuntimeABISpec entry for \(name), found \(registered.count)")
        let spec = try #require(registered.first)
        try #require(spec == self, "RuntimeABISpec inventory disagrees with canonical record \(name)")
        return spec
    }
}

@Suite
struct ABIMismatchTests {
    // MARK: - Helpers

    private typealias Symbol = RuntimeABISpecTestSymbol

    private func requireSpec(_ canonical: RuntimeABIFunctionSpec) throws -> RuntimeABIFunctionSpec {
        try canonical.requireRegistration()
    }

    // MARK: - Spec Integrity

    @Test
    func allParameterNamesAreNonEmpty() {
        for spec in RuntimeABISpec.allFunctions {
            for param in spec.parameters {
                #expect(
                    !(param.name.isEmpty),
                    "Parameter in '\(spec.name)' has an empty name"
                )
            }
        }
    }

    @Test
    func parameterNamesUniquePerFunction() {
        for spec in RuntimeABISpec.allFunctions {
            let names = spec.parameters.map { $0.name }
            let uniqueNames = Set(names)
            #expect(
                names.count == uniqueNames.count,
                "Duplicate parameter names in '\(spec.name)'"
            )
        }
    }

    @Test
    func collectionMutationSignaturesIncludeThrowingChannel() throws {
        let expected: [(spec: RuntimeABIFunctionSpec, parameters: [String])] = [
            (RuntimeABISpec.bridgeMutableListAddSpec, ["listRaw", "elem", "outThrown"]),
            (RuntimeABISpec.bridgeMutableListRemoveDispatchSpec, ["listRaw", "elem", "outThrown"]),
            (RuntimeABISpec.bridgeMutableSetAddSpec, ["setRaw", "elem", "outThrown"]),
            (RuntimeABISpec.bridgeMutableSetRemoveSpec, ["setRaw", "elem", "outThrown"]),
            (RuntimeABISpec.bridgeMutableSetClearSpec, ["setRaw", "outThrown"]),
            (RuntimeABISpec.bridgeMutableMapPutSpec, ["mapRaw", "key", "value", "outThrown"]),
            (RuntimeABISpec.bridgeMutableMapRemoveSpec, ["mapRaw", "key", "outThrown"]),
            (RuntimeABISpec.bridgeMutableMapClearSpec, ["mapRaw", "outThrown"]),
            (RuntimeABISpec.bridgeMutableMapPutAllSpec, ["mapRaw", "entriesRaw", "outThrown"]),
        ]
        for item in expected {
            let spec = try requireSpec(item.spec)
            #expect(spec.parameters.map(\.name) == item.parameters)
            #expect(spec.parameters.dropLast().allSatisfy { $0.type == .intptr })
            #expect(spec.parameters.last?.type == .nullableIntptrPointer)
            #expect(spec.isThrowing)
            #expect(!RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(spec.name))

            let extern = try #require(RuntimeABIExterns.externDecl(named: spec.name))
            #expect(extern.parameterTypes == spec.parameterTypeStrings)
            #expect(
                RuntimeABISpec.generateCHeader().contains(spec.cDeclaration),
                "Generated C header must expose the throwing collection mutation ABI for \(spec.name)"
            )
        }
    }

    @Test
    func legacyMutableListRemoveKeepsNonThrowingABI() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutableListRemoveSpec)
        #expect(spec.parameters.map(\.name) == ["listRaw", "elem"])
        #expect(spec.parameters.allSatisfy { $0.type == .intptr })
        #expect(!spec.isThrowing)
        let extern = try #require(RuntimeABIExterns.externDecl(named: spec.name))
        #expect(extern.parameterTypes == spec.parameterTypeStrings)
    }

    @Test
    func durationParsingBridgesMatchThrowingAndReturnContracts() throws {
        let expected: [(spec: RuntimeABIFunctionSpec, isThrowing: Bool)] = [
            (RuntimeABISpec.durationParseSpec, true),
            (RuntimeABISpec.durationParseOrNullSpec, false),
            (RuntimeABISpec.durationParseIsoStringSpec, true),
            (RuntimeABISpec.durationParseIsoStringOrNullSpec, false),
        ]

        for item in expected {
            let spec = try requireSpec(item.spec)
            let expectedTypes: [RuntimeABICType] = [.intptr]
                + (item.isThrowing ? [.nullableIntptrPointer] : [])
            #expect(spec.returnType == .intptr)
            #expect(spec.parameters.map(\.type) == expectedTypes)
            #expect(spec.isThrowing == item.isThrowing)
            #expect(
                RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(spec.name) == !item.isThrowing,
                "Non-throwing set disagrees with \(spec.name)"
            )
        }
    }

    @Test
    func listBoundsSignaturesIncludeThrowingChannel() throws {
        let expected: [(spec: RuntimeABIFunctionSpec, parameters: [String])] = [
            (RuntimeABISpec.bridgeListGetSpec, ["listRaw", "index", "outThrown"]),
            (RuntimeABISpec.listIteratorNextSpec, ["iterRaw", "outThrown"]),
            (RuntimeABISpec.iteratorNextSpec, ["iterRaw", "outThrown"]),
            (RuntimeABISpec.indexingIterableNextSpec, ["iterRaw", "outThrown"]),
            (RuntimeABISpec.bridgeMapIteratorNextSpec, ["iterRaw", "outThrown"]),
            (RuntimeABISpec.bridgeMutableMapIteratorNextSpec, ["iterRaw", "outThrown"]),
            (RuntimeABISpec.bridgeMutableListRemoveAtSpec, ["listRaw", "index", "outThrown"]),
        ]
        for item in expected {
            let spec = try requireSpec(item.spec)
            #expect(spec.parameters.map(\.name) == item.parameters)
            #expect(spec.parameters.dropLast().allSatisfy { $0.type == .intptr })
            #expect(spec.parameters.last?.type == .nullableIntptrPointer)
            #expect(spec.isThrowing)
            #expect(!RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(spec.name))

            let extern = try #require(RuntimeABIExterns.externDecl(named: spec.name))
            #expect(extern.parameterTypes == spec.parameterTypeStrings)
            #expect(
                RuntimeABISpec.generateCHeader().contains(spec.cDeclaration),
                "Generated C header must expose the throwing list bounds ABI for \(spec.name)"
            )
        }
    }

    @Test
    func charNumericBridgeABIsRemoved() {
        for name in [Symbol.runtime(.char, "to_int"), Symbol.runtime(.char, "to_long"), Symbol.runtime(.char, "to_uint"), Symbol.runtime(.char, "to_ulong")] {
            #expect(
                !RuntimeABISpec.allFunctions.contains { name.matches($0.name) },
                "Char numeric conversion bridge \(name) should be removed after KSP-1539"
            )
        }
    }

    @Test
    func longToCharBridgeABIIsRemoved() {
        #expect(
            !RuntimeABISpec.allFunctions.contains { Symbol.runtime(.long, "to_char").matches($0.name) },
            "Long.toChar should be provided by bundled Kotlin source, not RuntimeABI"
        )
    }

    @Test
    func unsignedToCharBridgeABIsRemoved() {
        for name in [Symbol.runtime(.uint, "to_char"), Symbol.runtime(.ulong, "to_char"), Symbol.runtime(.ubyte, "to_char"), Symbol.runtime(.ushort, "to_char")] {
            #expect(
                !RuntimeABISpec.allFunctions.contains { name.matches($0.name) },
                "\(name) should be removed: no unsigned type has toChar() in real Kotlin (BUG-251)"
            )
        }
    }

    // DEADCODE-014: source-backed reflection and collection migrations leave
    // no compiler, test, or runtime-internal consumer for these legacy exports.
    @Test
    func deadReflectionAndCollectionBridgeABIsAreRemoved() {
        let removedNames = [
            Symbol.bridge(.kfunction, "get_name"),
            Symbol.bridge(.kfunction, "get_arity"),
            Symbol.bridge(.kfunction, "get_return_type"),
            Symbol.runtime(.callableRef, "name"),
            Symbol.runtime(.callableRef, "arity"),
            Symbol.runtime(.callableRef, "is_suspend"),
            Symbol.runtime(.callableRef, "parameters"),
            Symbol.bridge(.kpropertyStub, "name"),
            Symbol.bridge(.kpropertyStub, "return_type"),
            Symbol.runtime(.indexedValue, "new"),
            Symbol.bridge(.mutableCollection, "addAll_sequence"),
        ]
        for name in removedNames {
            #expect(
                !RuntimeABISpec.allFunctions.contains { name.matches($0.name) },
                "\(name) should be removed after its source-backed migration"
            )
        }
    }

    @Test
    func floorDivABISignatures() throws {
        for name in [RuntimeABISpec.opFloorDivSpec, RuntimeABISpec.opLfloorDivSpec] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .intptr)
            #expect(spec.isThrowing)
            #expect(spec.parameters.map(\.type) == [.intptr, .intptr, .nullableIntptrPointer])
            #expect(spec.parameters.map(\.name) == ["lhs", "rhs", "outThrown"])
        }
    }

    // MARK: - J16.1 Signature Verification (spec-fixed)

    @Test
    func kkAllocSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.allocSpec)
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "size")
        #expect(spec.parameters[0].type == .uint32)
        #expect(spec.parameters[1].name == "typeInfo")
        #expect(
            spec.parameters[1].type == .constTypeInfoPointer,
            "\(spec.name) typeInfo must be const KTypeInfo * per J16.1"
        )
    }

    @Test
    func kkGcCollectSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.gcCollectSpec)
        #expect(spec.returnType == .void)
        // GC.collect() is a real bundled-source `object` member now, so the
        // GC receiver crosses the ABI as the sole parameter (see Platform.kt's
        // identical bridge functions for the established convention).
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkThreadLocalNewSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.threadLocalNewSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkThreadLocalGetOrSetSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.threadLocalGetOrSetSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "receiver")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "fnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkThrowableNewSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeThrowableNewSpec)
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .nullableOpaquePointer)
    }

    @Test
    func kkThrowableNewCauseSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeThrowableNewCauseSpec)
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkFloorModSignatures() throws {
        for name in [RuntimeABISpec.opFloorModSpec, RuntimeABISpec.opLfloorModSpec] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .intptr)
            #expect(spec.isThrowing)
            #expect(spec.parameters.map(\.type) == [.intptr, .intptr, .nullableIntptrPointer])
        }
    }

    /// Both accessors back Kotlin-source members of `Throwable`, so their
    /// runtime exports carry the hidden `outThrown` channel that every
    /// source-backed callee ABI appends.
    @Test
    func throwableRawStackFramesSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeThrowableRawStackFramesSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.isThrowing)
        #expect(spec.parameters.map(\.type) == [.intptr, .nullableIntptrPointer])
    }

    @Test
    func throwableToStringSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeThrowableToStringSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.isThrowing)
        #expect(spec.parameters.map(\.type) == [.intptr, .nullableIntptrPointer])
    }

    @Test
    func printStderrSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgePrintStderrSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkNoWhenBranchMatchedExceptionConstructorsSignature() throws {
        let noArg = try requireSpec(RuntimeABISpec.bridgeNoWhenBranchMatchedExceptionNewSpec)
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec(RuntimeABISpec.bridgeNoWhenBranchMatchedExceptionNewMessageSpec)
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])

        let messageCause = try requireSpec(RuntimeABISpec.bridgeNoWhenBranchMatchedExceptionNewMessageCauseSpec)
        #expect(messageCause.returnType == .intptr)
        #expect(messageCause.parameters.map(\.type) == [.intptr, .intptr])

        let cause = try requireSpec(RuntimeABISpec.bridgeNoWhenBranchMatchedExceptionNewCauseSpec)
        #expect(cause.returnType == .intptr)
        #expect(cause.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkConcurrentModificationExceptionConstructorsSignature() throws {
        let noArg = try requireSpec(RuntimeABISpec.bridgeConcurrentModificationExceptionNewSpec)
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec(RuntimeABISpec.bridgeConcurrentModificationExceptionNewMessageSpec)
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])

        let messageCause = try requireSpec(RuntimeABISpec.bridgeConcurrentModificationExceptionNewMessageCauseSpec)
        #expect(messageCause.returnType == .intptr)
        #expect(messageCause.parameters.map(\.type) == [.intptr, .intptr])

        let cause = try requireSpec(RuntimeABISpec.bridgeConcurrentModificationExceptionNewCauseSpec)
        #expect(cause.returnType == .intptr)
        #expect(cause.parameters.map(\.type) == [.intptr])
    }

    @Test
    func kkArrayIndexOutOfBoundsExceptionConstructorsSignature() throws {
        let noArg = try requireSpec(RuntimeABISpec.bridgeArrayIndexOutOfBoundsExceptionNewSpec)
        #expect(noArg.returnType == .intptr)
        #expect(noArg.parameters.count == 0)

        let message = try requireSpec(RuntimeABISpec.bridgeArrayIndexOutOfBoundsExceptionNewMessageSpec)
        #expect(message.returnType == .intptr)
        #expect(message.parameters.map(\.type) == [.intptr])
    }

    @Test
    func genericListAndArrayJoinToStringABIsAreSourceBacked() throws {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.runtime(.list, "joinToString").matches($0.name) }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.runtime(.array, "joinToString").matches($0.name) }) == nil
        )
        let privateBridge = try requireSpec(RuntimeABISpec.bridgeStringJoinToStringSpec)
        #expect(privateBridge.parameters.map(\.type) == [.intptr, .intptr, .intptr, .intptr])
        #expect(privateBridge.returnType == .intptr)
    }

    // KSP-621: Iterable.joinTo/joinToString and Sequence.joinTo/joinToString share
    // one bundled Kotlin implementation (Iterables.kt's appendJoinToAppendable*
    // helpers, called via iterator()), so the runtime bridges these
    // names used to route through when Sema left the callee unresolved are gone.
    @Test
    func iterableJoinToABIsAreSourceBacked() throws {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.bridge(.iterable, "joinTo").matches($0.name) }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.bridge(.iterable, "joinToString").matches($0.name) }) == nil
        )
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.bridge(.iterable, "joinToString_transform").matches($0.name) }) == nil
        )
    }

    @Test
    func kkThrowableIsCancellationSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.throwableIsCancellationSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkThrowableSuppressedRawSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeThrowableSuppressedRawSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkStringFromUTF8Signature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringFromUtf8Spec)
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .constUInt8Pointer)
        #expect(spec.parameters[1].type == .int32)
    }

    @Test
    func kkStringConcatPointerABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { Symbol.runtime(.string, "concat").matches($0.name) }),
            "String concat should use __kk_string_concat_flat instead of the legacy pointer ABI"
        )
    }

    @Test
    func kkStringRepeatPointerABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { Symbol.runtime(.string, "repeat").matches($0.name) }),
            "String repeat should use kk_string_repeat_flat instead of the legacy pointer ABI"
        )
    }

    @Test
    func kkStringSubstringAndReplaceSegmentPointerABIRemoved() {
        let legacyNames = stringSegmentMembers.map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should be removed in favor of bundled Kotlin source (StringSearchReplace.kt)"
            )
        }
    }

    // KSP-407: substringBefore/After/BeforeLast/AfterLast and
    // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin source
    // (StringSearchReplace.kt); neither the raw pointer nor the flattened
    // runtime ABI remains.
    @Test
    func kkStringSubstringAndReplaceSegmentFlatABIRemoved() {
        let removedNames = stringSegmentMembers.map { Symbol.runtime(.string, $0 + "_flat") }
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { removedName.matches($0.name) }),
                "\(removedName) should be removed in favor of bundled Kotlin source (StringSearchReplace.kt)"
            )
        }
    }

    private var stringSegmentMembers: [String] {
        [
            "substringBefore", "substringBeforeLast", "substringAfter", "substringAfterLast",
            "replaceAfter", "replaceAfterLast", "replaceBefore", "replaceBeforeLast",
        ].flatMap { [$0, $0 + "_char"] }
    }

    @Test
    func kkStringConcatFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeStringConcatFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 11)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplacePointerABIRemoved() {
        let legacyNames = [
            "replace",
            "replace_char",
            "replace_ignoreCase",
            "replace_char_ignoreCase",
        ].map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    // KSP-404: startsWith/endsWith/removePrefix/removeSuffix/removeSurrounding are
    // bundled Kotlin source (StringPrefixSuffix.kt); neither the raw pointer nor
    // the flattened runtime ABI remains.
    @Test
    func kkStringPrefixSuffixABIRemoved() {
        let removedNames = [
            "startsWith",
            "startsWith_flat",
            "endsWith",
            "endsWith_flat",
            "removePrefix",
            "removePrefix_flat",
            "removeSuffix",
            "removeSuffix_flat",
            "removeSurrounding",
            "removeSurrounding_flat",
            "removeSurrounding_pair",
            "removeSurrounding_pair_flat",
        ].map { Symbol.runtime(.string, $0) }
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { removedName.matches($0.name) }),
                "\(removedName) should be removed in favor of bundled Kotlin source (StringPrefixSuffix.kt)"
            )
        }
    }

    @Test
    func kkStringReplaceFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringReplaceFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 15)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceCharFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringReplaceCharFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 9)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringReplaceIgnoreCaseFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 16)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceCharIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringReplaceCharIgnoreCaseFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 10)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringReplaceFirstRangePointerABIRemoved() {
        let legacyNames = [
            "replaceFirst",
            "replaceFirst_ignoreCase",
            "replaceRange",
            "removeRange",
            "removeRange_range",
        ].map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringReplaceFirstFlatSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.stringReplaceFirstFlatSpec)
        #expect(spec.returnType == .nullableUInt8Pointer)
        #expect(spec.parameters.count == 15)
        #expect(spec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringSubstringSliceRangeABIRemoved() {
        // KSP-406: substring / subSequence / slice / removeRange / replaceRange are
        // bundled Kotlin source with no String-specific runtime ABI (raw or flat).
        let removedNames = [
            "substring",
            "substring_flat",
            "subSequence",
            "subSequence_flat",
            "slice_range",
            "slice_iterable",
            "removeRange",
            "removeRange_flat",
            "removeRange_range",
            "removeRange_range_flat",
            "replaceRange",
            "replaceRange_flat",
            "replaceRange_indices",
        ].map { Symbol.runtime(.string, $0) }
        for removedName in removedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { removedName.matches($0.name) }),
                "\(removedName) should be removed: substring/slice/range edits are source-backed after KSP-406"
            )
        }
    }

    @Test
    func kkStringPadABIRemoved() {
        let legacyNames = [
            "padStart_default",
            "padEnd_default",
            "padStart",
            "padEnd",
            "padStart_default_flat",
            "padEnd_default_flat",
            "padStart_flat",
            "padEnd_flat",
        ].map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should be removed because String pad APIs are source-backed"
            )
        }
    }

    @Test
    func kkStringTrimPointerABIRemoved() {
        let legacyNames = [
            "trim",
            "trim_predicate",
            "trimStart",
            "trimStart_predicate",
            "trimEnd",
            "trimEnd_predicate",
        ].map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringTrimPredicateFlatSignatures() throws {
        let names = [
            RuntimeABISpec.stringTrimPredicateFlatSpec,
            RuntimeABISpec.stringTrimStartPredicateFlatSpec,
            RuntimeABISpec.stringTrimEndPredicateFlatSpec,
        ]
        for name in names {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 10)
            #expect(spec.parameters.map(\.type) == [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    @Test
    func kkStringIfBlankEmptyFlatCompatibilitySignatures() throws {
        for name in [RuntimeABISpec.stringIfBlankFlatSpec, RuntimeABISpec.stringIfEmptyFlatSpec] {
            let spec = try requireSpec(name)
            #expect(spec.returnType == .nullableUInt8Pointer)
            #expect(spec.parameters.count == 10)
        }
    }

    @Test
    func kkStringReplaceFirstCharABIRemoved() {
        #expect(
            !(RuntimeABISpec.allFunctions.contains { Symbol.runtime(.string, "replaceFirstChar").matches($0.name) }),
            "String.replaceFirstChar must have no legacy runtime ABI now that it is source-backed"
        )
        #expect(
            !(RuntimeABISpec.allFunctions.contains { Symbol.runtime(.string, "replaceFirstChar_flat").matches($0.name) }),
            "String.replaceFirstChar must have no flattened runtime ABI now that it is source-backed"
        )
    }

    @Test
    func kkStringCommonPrefixSuffixRuntimeABIRemoved() {
        let migratedNames = [
            "commonPrefixWith",
            "commonSuffixWith",
            "commonPrefixWith_ignoreCase",
            "commonSuffixWith_ignoreCase",
            "commonPrefixWith_flat",
            "commonSuffixWith_flat",
            "commonPrefixWith_ignoreCase_flat",
            "commonSuffixWith_ignoreCase_flat",
        ].map { Symbol.runtime(.string, $0) }
        for migratedName in migratedNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { migratedName.matches($0.name) }),
                "\(migratedName) should be provided by bundled Kotlin source, not runtime ABI"
            )
        }
    }

    @Test
    func kkStringFormatPointerABIRemoved() {
        for legacyName in [Symbol.runtime(.string, "format"), Symbol.runtime(.string, "format_locale")] {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    /// KSP-418: `String.format` is a private stdlib bridge, so only `__kk_`-prefixed
    /// entry points may exist.
    @Test
    func kkStringFormatPublicNamesDemoted() {
        for publicName in [Symbol.runtime(.string, "format_flat"), Symbol.runtime(.string, "format_locale_flat")] {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { publicName.matches($0.name) }),
                "\(publicName) should be demoted to the __kk_ bridge namespace"
            )
        }
    }

    @Test
    func kkStringFormatFlatSignatures() throws {
        let formatSpec = try requireSpec(RuntimeABISpec.bridgeStringFormatFlatSpec)
        #expect(formatSpec.isThrowing)
        #expect(formatSpec.returnType == .nullableUInt8Pointer)
        #expect(formatSpec.parameters.map(\.type) == [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])

        let localeSpec = try requireSpec(RuntimeABISpec.bridgeStringFormatLocaleFlatSpec)
        #expect(localeSpec.isThrowing)
        #expect(localeSpec.returnType == .nullableUInt8Pointer)
        #expect(localeSpec.parameters.map(\.type) == [
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    @Test
    func kkStringIndentPointerABIRemoved() {
        let legacyNames = [
            "trimIndent",
            "trimMargin_default",
            "trimMargin",
            "prependIndent_default",
            "prependIndent",
            "replaceIndent_default",
            "replaceIndent",
            "replaceIndentByMargin",
        ].map { Symbol.runtime(.string, $0) }
        for legacyName in legacyNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { legacyName.matches($0.name) }),
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    @Test
    func kkStringIndentFlatABIRemoved() {
        let flatNames = [
            "trimIndent_flat",
            "trimMargin_default_flat",
            "trimMargin_flat",
            "prependIndent_default_flat",
            "prependIndent_flat",
            "replaceIndent_default_flat",
            "replaceIndent_flat",
            "replaceIndentByMargin_flat",
        ].map { Symbol.runtime(.string, $0) }
        for name in flatNames {
            #expect(
                !(RuntimeABISpec.allFunctions.contains { name.matches($0.name) }),
                "\(name) should be provided by bundled Kotlin source, not the flattened runtime ABI"
            )
        }
    }

    @Test
    func printRawSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgePrintRawSpec)
        #expect(spec.returnType == .void)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func printlnRawSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgePrintlnRawSpec)
        #expect(spec.returnType == .void)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func stringLengthHasNoRuntimeABISignature() {
        #expect(
            RuntimeABISpec.allFunctions.first(where: { Symbol.runtime(.string, "struct_get_length").matches($0.name) }) == nil,
            "String.length is lowered as an aggregate field extract and must not have a runtime ABI entry"
        )
    }

    @Test
    func kkOpIsSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.opIsSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkCoroutineSuspendedSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.coroutineSuspendedSpec)
        #expect(spec.returnType == .opaquePointer)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkCreateCoroutineUninterceptedSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.createCoroutineUninterceptedSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "entryPointRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "completionContinuation")
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkStartCoroutineUninterceptedOrReturnSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.startCoroutineUninterceptedOrReturnSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 3)
        #expect(spec.parameters[0].name == "entryPointRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "continuation")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "outThrown")
        #expect(spec.parameters[2].type == .nullableIntptrPointer)
    }

    @Test
    func kkSuspendFunctionInvokeSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.suspendFunctionInvokeSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "functionRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "arg")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "continuation")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkSuspendFunctionInvokeZeroAritySignature() throws {
        let spec = try requireSpec(RuntimeABISpec.suspendFunctionInvoke0Spec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 3)
        #expect(spec.parameters[0].name == "functionRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "continuation")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "outThrown")
        #expect(spec.parameters[2].type == .nullableIntptrPointer)
    }

    @Test
    func kkSuspendFunctionInvokeTwoAritySignature() throws {
        let spec = try requireSpec(RuntimeABISpec.suspendFunctionInvoke2Spec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.map(\.name) == ["functionRaw", "arg1", "arg2", "continuation", "outThrown"])
        #expect(spec.parameters.map(\.type) == [.intptr, .intptr, .intptr, .intptr, .nullableIntptrPointer])
    }

    @Test
    func kkSuspendFunctionCreateSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.suspendFunctionCreateSpec)
        #expect(spec.returnType == .intptr)
        #expect(!spec.isThrowing)
        #expect(spec.parameters.map(\.name) == ["bodyRaw", "closureRaw", "arity", "entryPointRaw"])
        #expect(spec.parameters.map(\.type) == [.intptr, .intptr, .intptr, .intptr])
    }

    @Test
    func kkSuspendFunctionInvokeThreeAritySignature() throws {
        let spec = try requireSpec(RuntimeABISpec.suspendFunctionInvoke3Spec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.map(\.name) == ["functionRaw", "arg1", "arg2", "arg3", "continuation", "outThrown"])
        #expect(spec.parameters.map(\.type) == [.intptr, .intptr, .intptr, .intptr, .intptr, .nullableIntptrPointer])
    }

    @Test
    func kkMutableListAddAtSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutableListAddAtSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "listRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "index")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "element")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutableListSetSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutableListSetSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "listRaw")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "index")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "element")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkListSortedPrimitiveSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedPrimitiveSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .int32)
    }

    @Test
    func kkListSortedDescendingSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedDescendingSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkListSortedBySignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedBySpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByPrimitiveSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedByPrimitiveSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByDescendingSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedByDescendingSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedByDescendingPrimitiveSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 5)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .int32)
        #expect(spec.parameters[4].type == .nullableIntptrPointer)
    }

    @Test
    func kkListSortedWithSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.listSortedWithSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkLockWithLockSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeLockWithLockSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "actionFnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    // KSP-618: kotlin.synchronized is Kotlin source over this demoted bridge.
    @Test
    func kkSynchronizedSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeSynchronizedSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 4)
        #expect(spec.parameters[0].name == "lock")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "fnPtr")
        #expect(spec.parameters[1].type == .intptr)
        #expect(spec.parameters[2].name == "closureRaw")
        #expect(spec.parameters[2].type == .intptr)
        #expect(spec.parameters[3].name == "outThrown")
        #expect(spec.parameters[3].type == .nullableIntptrPointer)
    }

    @Test
    func kkMutexCreateSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutexCreateSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 0)
    }

    @Test
    func kkMutexLockSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.mutexLockSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "continuation")
        #expect(spec.parameters[1].type == .intptr)
    }

    @Test
    func kkMutexUnlockSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.mutexUnlockSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "outThrown")
        #expect(spec.parameters[1].type == .nullableIntptrPointer)
        #expect(spec.isThrowing)
        #expect(!RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(spec.name))
    }

    @Test
    func kkMutexTryLockSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutexTryLockSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkMutexIsLockedSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.bridgeMutexIsLockedSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 1)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
    }

    @Test
    func kkSemaphoreReleaseSignature() throws {
        let spec = try requireSpec(RuntimeABISpec.semaphoreReleaseSpec)
        #expect(spec.returnType == .intptr)
        #expect(spec.parameters.count == 2)
        #expect(spec.parameters[0].name == "handle")
        #expect(spec.parameters[0].type == .intptr)
        #expect(spec.parameters[1].name == "outThrown")
        #expect(spec.parameters[1].type == .nullableIntptrPointer)
        #expect(spec.isThrowing)
        #expect(!RuntimeABISpec.nonThrowingRuntimeCalleeNames.contains(spec.name))
    }

    // KSP-677: kk_mutex_withLock removed — Mutex.withLock is Kotlin source.

    // MARK: - Header Generation

    @Test
    func generatedHeaderContainsGuard() {
        let header = RuntimeABISpec.generateCHeader()
        #expect(header.contains("#ifndef KK_RUNTIME_ABI_H"))
        #expect(header.contains("#define KK_RUNTIME_ABI_H"))
        #expect(header.contains("#endif"))
    }

    @Test
    func generatedHeaderContainsAllFunctions() {
        let header = RuntimeABISpec.generateCHeader()
        let headerLines = Set(
            header
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        )
        for spec in RuntimeABISpec.allFunctions {
            #expect(
                headerLines.contains(spec.cDeclaration),
                "Generated header missing declaration for '\(spec.name)': expected line '\(spec.cDeclaration)'"
            )
        }
    }

    @Test
    func generatedHeaderContainsSpecVersion() {
        let header = RuntimeABISpec.generateCHeader()
        #expect(header.contains(RuntimeABISpec.specVersion))
    }

}
