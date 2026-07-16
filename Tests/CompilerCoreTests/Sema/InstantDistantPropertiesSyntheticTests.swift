#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct InstantDistantPropertiesSyntheticTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected Instant distant properties to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    // KSP-472: epochSeconds, nanosecondsOfSecond, isDistantPast, isDistantFuture,
    // plus, minus (Duration and Instant overloads), and compareTo are now Kotlin
    // source extension properties/functions/operators in Stdlib/kotlin/time/Instant.kt
    // that delegate to __kk_instant_* bridge methods registered on the Instant class
    // itself.
    @Test func testInstantBridgeMethodsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let instantFQName = kotlinTime + [interner.intern("Instant")]
        let instantSymbol = try #require(sema.symbols.lookup(fqName: instantFQName))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let durationFQName = kotlinTime + [interner.intern("Duration")]
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        let expectedBridges: [(name: String, link: String, parameterTypes: [TypeID], returnType: TypeID)] = [
            ("__kk_instant_epoch_seconds", "kk_instant_epoch_seconds", [], sema.types.longType),
            ("__kk_instant_nano_of_second", "kk_instant_nano_of_second", [], sema.types.intType),
            ("__kk_instant_is_distant_past", "kk_instant_is_distant_past", [], boolType),
            ("__kk_instant_is_distant_future", "kk_instant_is_distant_future", [], boolType),
            ("__kk_instant_plus_duration", "kk_instant_plus_duration", [durationType], instantType),
            ("__kk_instant_minus_duration", "kk_instant_minus_duration", [durationType], instantType),
            ("__kk_instant_compare", "kk_instant_compare", [instantType], sema.types.intType),
            ("__kk_instant_until", "kk_instant_until", [instantType], durationType),
        ]

        for bridge in expectedBridges {
            let bridgeFQName = instantFQName + [interner.intern(bridge.name)]
            let matchingSymbols = sema.symbols.lookupAll(fqName: bridgeFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == instantType
                    && signature.parameterTypes == bridge.parameterTypes
            }
            #expect(matchingSymbols.count == 1, "Expected exactly one Instant.\(bridge.name) bridge with receiverType=Instant")
            let symbol = try #require(matchingSymbols.first)
            #expect(sema.symbols.symbol(symbol)?.kind == .function)
            #expect(!(sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true), "Instant.\(bridge.name) bridge must not be marked as an operator")
            #expect(sema.symbols.externalLinkName(for: symbol) == bridge.link)
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == bridge.returnType)
        }
    }

    // KSP-472: verify the public API is resolved via Kotlin source
    // (Stdlib/kotlin/time/Instant.kt), not via direct synthetic stubs.
    @Test func testInstantKotlinSourceExtensionsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let instantFQName = kotlinTime + [interner.intern("Instant")]
        let instantSymbol = try #require(sema.symbols.lookup(fqName: instantFQName))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let durationFQName = kotlinTime + [interner.intern("Duration")]
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        // epochSeconds / nanosecondsOfSecond / isDistantPast / isDistantFuture are
        // Kotlin source extension properties at package scope.
        let extensionProperties: [(name: String, type: TypeID)] = [
            ("epochSeconds", sema.types.longType),
            ("nanosecondsOfSecond", sema.types.intType),
            ("isDistantPast", boolType),
            ("isDistantFuture", boolType),
        ]
        for property in extensionProperties {
            let fqName = kotlinTime + [interner.intern(property.name)]
            let symbol = try #require(
                sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .property
                        && sema.symbols.propertyType(for: symbolID) == property.type
                        && sema.symbols.extensionPropertyReceiverType(for: symbolID) == instantType
                },
                "Instant.\(property.name) should be a Kotlin source extension property at kotlin.time scope"
            )
            #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Instant.\(property.name) should have a declSite (Kotlin source)")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil, "Instant.\(property.name) should have no C external link name (Kotlin source)")
        }

        // plus / minus (Duration and Instant overloads) / compareTo are Kotlin
        // source extension operator functions. minus(Instant) returns Duration
        // (t2 - t1), matching real kotlin.time.Instant; there is no until().
        let operators: [(name: String, parameterTypes: [TypeID], returnType: TypeID)] = [
            ("plus", [durationType], instantType),
            ("minus", [durationType], instantType),
            ("minus", [instantType], durationType),
            ("compareTo", [instantType], sema.types.intType),
        ]
        for op in operators {
            let fqName = kotlinTime + [interner.intern(op.name)]
            let symbol = try #require(
                sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == instantType && sig.parameterTypes == op.parameterTypes
                },
                "Instant.\(op.name) should be a Kotlin source extension function at kotlin.time scope"
            )
            #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Instant.\(op.name) should have a declSite (Kotlin source)")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil, "Instant.\(op.name) should have no C external link name (Kotlin source)")
        }

        // elapsed is a Kotlin source extension function.
        let elapsedFQName = kotlinTime + [interner.intern("elapsed")]
        let elapsedSymbol = try #require(
            sema.symbols.lookupAll(fqName: elapsedFQName).first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.receiverType == instantType && sig.parameterTypes.isEmpty
            },
            "Instant.elapsed should be a Kotlin source extension function at kotlin.time scope"
        )
        #expect(sema.symbols.symbol(elapsedSymbol)?.declSite != nil)
        #expect(sema.symbols.externalLinkName(for: elapsedSymbol) == nil)
    }

    // KSP-472: now() / fromEpochMilliseconds() stay as direct companion factory
    // stubs — Kotlin source cannot declare an extension whose receiver is
    // Instant.Companion.
    @Test func testInstantCompanionFactoriesRemainDirectStubs() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let instantFQName = kotlinTime + [interner.intern("Instant")]
        let instantSymbol = try #require(sema.symbols.lookup(fqName: instantFQName))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionFQName = instantFQName + [interner.intern("Companion")]

        let nowFQName = companionFQName + [interner.intern("now")]
        let nowSymbol = try #require(sema.symbols.lookupAll(fqName: nowFQName).first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty && sig.returnType == instantType
        })
        #expect(sema.symbols.externalLinkName(for: nowSymbol) == "kk_instant_now")

        let fromEpochFQName = companionFQName + [interner.intern("fromEpochMilliseconds")]
        let fromEpochSymbol = try #require(sema.symbols.lookupAll(fqName: fromEpochFQName).first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes == [sema.types.longType] && sig.returnType == instantType
        })
        #expect(sema.symbols.externalLinkName(for: fromEpochSymbol) == "kk_instant_from_epoch_millis")
    }

    @Test func testInstantDistantPropertiesResolveInSource() throws {
        let source = """
        import kotlin.time.*

        fun flags(instant: Instant): Boolean {
            return instant.isDistantPast || instant.isDistantFuture
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let flagsSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("flags")]))
        let signature = try #require(sema.symbols.functionSignature(for: flagsSymbol))
        #expect(signature.returnType == sema.types.make(.primitive(.boolean, .nonNull)))
    }
}
#endif
