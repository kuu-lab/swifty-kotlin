#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DurationSyntheticStubTests {
    @Test
    func testDurationOperatorBridgesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Verify __kk_duration_* bridge stubs (MIGRATION-TIME-001)
        let expectedBridges: [(name: String, link: String, parameterTypes: [TypeID])] = [
            ("__kk_duration_plus", "kk_duration_plus", [durationType]),
            ("__kk_duration_minus", "kk_duration_minus", [durationType]),
            ("__kk_duration_times_int", "kk_duration_times_int", [sema.types.intType]),
            ("__kk_duration_div_int", "kk_duration_div_int", [sema.types.intType]),
            ("__kk_duration_div_duration", "kk_duration_div_duration", [durationType]),
            ("__kk_duration_unary_minus", "kk_duration_unary_minus", []),
            ("__kk_duration_absoluteValue", "kk_duration_absoluteValue", []),
            ("__kk_duration_isNegative", "kk_duration_isNegative", []),
            ("__kk_duration_isPositive", "kk_duration_isPositive", []),
            ("__kk_duration_isInfinite", "kk_duration_isInfinite", []),
        ]

        for bridge in expectedBridges {
            let bridgeFQName = durationFQName + [interner.intern(bridge.name)]
            let matchingSymbols = sema.symbols.lookupAll(fqName: bridgeFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == durationType
                    && signature.parameterTypes == bridge.parameterTypes
            }
            #expect(matchingSymbols.count == 1, "Expected exactly one Duration.\(bridge.name) bridge with receiverType=Duration")
            let symbol = try #require(matchingSymbols.first)
            #expect(sema.symbols.symbol(symbol)?.kind == .function)
            #expect(!(sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true), "Duration.\(bridge.name) bridge must not be marked as an operator")
            #expect(sema.symbols.externalLinkName(for: symbol) == bridge.link)
        }

        // compareTo is not in MIGRATION-TIME-001 scope — verify it stays as a direct stub
        let compareToFQName = durationFQName + [interner.intern("compareTo")]
        let compareToSymbol = try #require(sema.symbols.lookupAll(fqName: compareToFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == durationType && signature.parameterTypes == [durationType]
        })
        #expect(sema.symbols.externalLinkName(for: compareToSymbol) == "kk_duration_compareTo")
        #expect(sema.symbols.symbol(compareToSymbol)?.flags.contains(.operatorFunction) == true, "Duration.compareTo should remain an operatorFunction")
    }

    // MIGRATION-TIME-001 complete: operators and predicates are now Kotlin source extension
    // functions/properties in Stdlib/kotlin/time/Duration.kt (no direct compat stubs).
    @Test
    func testDurationKotlinSourceOperatorsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        // Arithmetic operators are Kotlin source extension functions at package scope.
        let arithmeticOps: [(name: String, parameterTypes: [TypeID])] = [
            ("plus", [durationType]),
            ("minus", [durationType]),
            ("times", [sema.types.intType]),
            ("div", [sema.types.intType]),
            ("div", [durationType]),
            ("unaryMinus", []),
        ]
        for op in arithmeticOps {
            let packageFQName = ["kotlin", "time", op.name].map { interner.intern($0) }
            let sym = try #require(
                sema.symbols.lookupAll(fqName: packageFQName).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == durationType && sig.parameterTypes == op.parameterTypes
                },
                "Duration.\(op.name) should be a Kotlin source extension function at kotlin.time scope"
            )
            #expect(sema.symbols.symbol(sym)?.declSite != nil, "Duration.\(op.name) should have a declSite (Kotlin source, not a synthetic stub)")
            #expect(sema.symbols.externalLinkName(for: sym) == nil, "Duration.\(op.name) should have no C external link name (Kotlin source)")
        }

        // absoluteValue is a Kotlin source extension property at package scope.
        // Extension properties are represented as property symbols (kind == .property) with
        // an associated getter accessor that carries the function signature.
        let absValFQName = ["kotlin", "time", "absoluteValue"].map { interner.intern($0) }
        let absValSym = try #require(
            sema.symbols.lookupAll(fqName: absValFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.propertyType(for: symbolID) == durationType
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == durationType
            },
            "Duration.absoluteValue should be a Kotlin source extension property at kotlin.time scope"
        )
        #expect(sema.symbols.symbol(absValSym)?.declSite != nil, "Duration.absoluteValue should have a declSite (Kotlin source)")
        #expect(sema.symbols.externalLinkName(for: absValSym) == nil, "Duration.absoluteValue should have no C external link name (Kotlin source)")

        // isNegative, isPositive, isInfinite are Kotlin source extension functions at package scope.
        let predicates = ["isNegative", "isPositive", "isInfinite"]
        for name in predicates {
            let fqName = ["kotlin", "time", name].map { interner.intern($0) }
            let sym = try #require(
                sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == durationType && sig.parameterTypes.isEmpty
                },
                "Duration.\(name) should be a Kotlin source extension function at kotlin.time scope"
            )
            #expect(sema.symbols.symbol(sym)?.declSite != nil, "Duration.\(name) should have a declSite (Kotlin source)")
            #expect(sema.symbols.externalLinkName(for: sym) == nil, "Duration.\(name) should have no C external link name (Kotlin source)")
        }
    }

    @Test
    func testDurationSourceOperatorsDoNotPoisonLambdaArithmeticFallback() throws {
        let source = """
        fun main() {
            val square = { x: Int -> x * x }
            square(5)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Duration source extension operators should not block primitive arithmetic fallback: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func testDurationIsoAndParseSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        // MIGRATION-TIME-002: toIsoString is now a Kotlin-source extension function at
        // package scope ["kotlin","time","toIsoString"], not a synthetic stub member.
        let toIsoPackageFQName = ["kotlin", "time", "toIsoString"].map { interner.intern($0) }
        let toIsoSymbol = try #require(sema.symbols.lookupAll(fqName: toIsoPackageFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == durationType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        #expect(sema.symbols.externalLinkName(for: toIsoSymbol) == nil, "Duration.toIsoString should be a bundled Kotlin function with no C external link (MIGRATION-TIME-002)")
        #expect(sema.symbols.symbol(toIsoSymbol)?.declSite != nil, "Duration.toIsoString should have a declSite (Kotlin source, not a synthetic stub)")

        let companionFQName = durationFQName + [interner.intern("Companion")]
        let parseFQName = companionFQName + [interner.intern("parse")]
        let parseSymbol = try #require(sema.symbols.lookupAll(fqName: parseFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        #expect(sema.symbols.externalLinkName(for: parseSymbol) == "kk_duration_parse")
        #expect(sema.symbols.symbol(parseSymbol)?.flags.contains(.throwingFunction) == true, "Duration.parse should use the thrown channel for invalid input")

        let parseOrNullFQName = companionFQName + [interner.intern("parseOrNull")]
        let parseOrNullSymbol = try #require(sema.symbols.lookupAll(fqName: parseOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        #expect(sema.symbols.externalLinkName(for: parseOrNullSymbol) == "kk_duration_parseOrNull")

        let parseIsoFQName = companionFQName + [interner.intern("parseIsoString")]
        let parseIsoSymbol = try #require(sema.symbols.lookupAll(fqName: parseIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        #expect(sema.symbols.externalLinkName(for: parseIsoSymbol) == "kk_duration_parseIsoString")
        #expect(sema.symbols.symbol(parseIsoSymbol)?.flags.contains(.throwingFunction) == true, "Duration.parseIsoString should use the thrown channel for invalid input")

        let parseIsoOrNullFQName = companionFQName + [interner.intern("parseIsoStringOrNull")]
        let parseIsoOrNullSymbol = try #require(sema.symbols.lookupAll(fqName: parseIsoOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        #expect(sema.symbols.externalLinkName(for: parseIsoOrNullSymbol) == "kk_duration_parseIsoStringOrNull")
    }

    @Test
    func testDurationToComponentsOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        // MIGRATION-TIME-002: toComponents overloads are now Kotlin-source extension functions
        // at package scope ["kotlin","time","toComponents"], not synthetic stubs.
        let oldToComponentsFQName = durationFQName + [interner.intern("toComponents")]
        let oldCLinkNames = [
            "kk_duration_toComponents_seconds",
            "kk_duration_toComponents_minutes",
            "kk_duration_toComponents_hours",
            "kk_duration_toComponents_days",
        ]
        for linkName in oldCLinkNames {
            #expect(!(sema.symbols.lookupAll(fqName: oldToComponentsFQName).contains { symbolID in
                    sema.symbols.externalLinkName(for: symbolID) == linkName
                }), "Duration.toComponents should no longer have C stub '\(linkName)' (MIGRATION-TIME-002)")
        }

        let toComponentsFQName = ["kotlin", "time", "toComponents"].map { interner.intern($0) }
        let expectedLambdaArities = [2, 3, 4, 5]
        for expectedArity in expectedLambdaArities {
            let symbol = try #require(sema.symbols.lookupAll(fqName: toComponentsFQName).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID),
                          sig.receiverType == durationType,
                          sig.parameterTypes.count == 1,
                          case let .functionType(ft) = sema.types.kind(
                              of: sema.types.makeNonNullable(sig.parameterTypes[0]))
                    else { return false }
                    return ft.params.count == expectedArity
                })
            #expect(sema.symbols.symbol(symbol)?.declSite != nil, "Duration.toComponents (arity \(expectedArity)) should have a declSite (Kotlin source)")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil, "Duration.toComponents (arity \(expectedArity)) should have no C external link")
        }
    }

    @Test
    func testNumericToDurationExtensionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let durationUnitFQName = ["kotlin", "time", "DurationUnit"].map { interner.intern($0) }
        let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: durationUnitFQName))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toDurationFQName = ["kotlin", "time", "toDuration"].map { interner.intern($0) }
        let expected: [(receiver: TypeID, link: String)] = [
            (sema.types.intType, "kk_duration_toDuration_int"),
            (sema.types.longType, "kk_duration_toDuration_long"),
            (sema.types.doubleType, "kk_duration_toDuration_double"),
        ]

        for overload in expected {
            let symbol = try #require(sema.symbols.lookupAll(fqName: toDurationFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == overload.receiver
                    && signature.parameterTypes == [durationUnitType]
                    && signature.returnType == durationType
            })
            #expect(sema.symbols.symbol(symbol)?.kind == .function)
            #expect(sema.symbols.externalLinkName(for: symbol) == overload.link)
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.valueParameterSymbols.count == 1)
            #expect(sema.symbols.propertyType(for: signature.valueParameterSymbols[0]) == durationUnitType)
        }
    }
}
#endif
