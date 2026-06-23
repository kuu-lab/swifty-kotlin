@testable import CompilerCore
import XCTest

final class DurationSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MIGRATION-TIME-001: plus, minus, times, div, unaryMinus are implemented in
    // BundledKotlinStdlib.kotlinTimeSource via __kk_duration_* bridge stubs. Direct operator
    // stubs (plus, minus, …) are kept as backward-compatible dispatch targets until
    // collectMemberFunctionCandidates probes kotlin.time extension functions. This test verifies:
    //   (a) The __kk_duration_* bridge stubs exist with correct ABI link names.
    //   (b) compareTo remains as a direct synthetic stub (not in migration scope).
    func testDurationOperatorBridgesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
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
            XCTAssertEqual(
                matchingSymbols.count,
                1,
                "Expected exactly one Duration.\(bridge.name) bridge with receiverType=Duration"
            )
            let symbol = try XCTUnwrap(matchingSymbols.first)
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertFalse(
                sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true,
                "Duration.\(bridge.name) bridge must not be marked as an operator"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), bridge.link)
        }

        // compareTo is not in MIGRATION-TIME-001 scope — verify it stays as a direct stub
        let compareToFQName = durationFQName + [interner.intern("compareTo")]
        let compareToSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: compareToFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == durationType && signature.parameterTypes == [durationType]
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: compareToSymbol), "kk_duration_compareTo")
        XCTAssertTrue(
            sema.symbols.symbol(compareToSymbol)?.flags.contains(.operatorFunction) == true,
            "Duration.compareTo should remain an operatorFunction"
        )
    }

    // MIGRATION-TIME-001 compat layer: direct operator stubs kept for member dispatch.
    func testDurationDirectDispatchStubsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        // absoluteValue should be a property stub
        let absValFQName = durationFQName + [interner.intern("absoluteValue")]
        let absValSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: absValFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: absValSymbol), "kk_duration_absoluteValue")

        // isNegative, isPositive, isInfinite should be function stubs (not properties)
        let predicateBridges: [(name: String, link: String)] = [
            ("isNegative", "kk_duration_isNegative"),
            ("isPositive", "kk_duration_isPositive"),
            ("isInfinite", "kk_duration_isInfinite"),
        ]
        for predicate in predicateBridges {
            let fqn = durationFQName + [interner.intern(predicate.name)]
            let sym = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fqn).first { symbolID in
                    guard let s = sema.symbols.symbol(symbolID) else { return false }
                    return s.kind == .function
                },
                "Duration.\(predicate.name) function stub not found"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: sym), predicate.link)
        }

        // Operator stubs (plus, minus, times, div×2, unaryMinus)
        let operatorStubs: [(name: String, link: String, parameterTypes: [TypeID])] = [
            ("plus", "kk_duration_plus", [durationType]),
            ("minus", "kk_duration_minus", [durationType]),
            ("times", "kk_duration_times_int", [sema.types.intType]),
            ("div", "kk_duration_div_int", [sema.types.intType]),
            ("div", "kk_duration_div_duration", [durationType]),
            ("unaryMinus", "kk_duration_unary_minus", []),
        ]
        for stub in operatorStubs {
            let fqn = durationFQName + [interner.intern(stub.name)]
            let sym = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fqn).first { symbolID in
                    guard let s = sema.symbols.symbol(symbolID),
                          s.kind == .function,
                          let sig = sema.symbols.functionSignature(for: symbolID)
                    else { return false }
                    return sig.receiverType == durationType && sig.parameterTypes == stub.parameterTypes
                },
                "Duration.\(stub.name)(\(stub.parameterTypes)) operator stub not found"
            )
            XCTAssertTrue(
                sema.symbols.symbol(sym)?.flags.contains(.operatorFunction) == true,
                "Duration.\(stub.name) must be an operatorFunction"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: sym), stub.link)
        }
    }

    func testDurationIsoAndParseSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toIsoFQName = durationFQName + [interner.intern("toIsoString")]
        let toIsoSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == durationType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: toIsoSymbol), "kk_duration_toIsoString")
        XCTAssertFalse(
            sema.symbols.symbol(toIsoSymbol)?.flags.contains(.operatorFunction) == true,
            "Duration.toIsoString should not be registered as an operator"
        )

        let companionFQName = durationFQName + [interner.intern("Companion")]
        let parseFQName = companionFQName + [interner.intern("parse")]
        let parseSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseSymbol), "kk_duration_parse")
        XCTAssertTrue(
            sema.symbols.symbol(parseSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parse should use the thrown channel for invalid input"
        )

        let parseOrNullFQName = companionFQName + [interner.intern("parseOrNull")]
        let parseOrNullSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseOrNullSymbol), "kk_duration_parseOrNull")

        let parseIsoFQName = companionFQName + [interner.intern("parseIsoString")]
        let parseIsoSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == durationType
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseIsoSymbol), "kk_duration_parseIsoString")
        XCTAssertTrue(
            sema.symbols.symbol(parseIsoSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parseIsoString should use the thrown channel for invalid input"
        )

        let parseIsoOrNullFQName = companionFQName + [interner.intern("parseIsoStringOrNull")]
        let parseIsoOrNullSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: parseIsoOrNullFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.parameterTypes == [sema.types.stringType]
                && signature.returnType == sema.types.makeNullable(durationType)
        })
        XCTAssertEqual(sema.symbols.externalLinkName(for: parseIsoOrNullSymbol), "kk_duration_parseIsoStringOrNull")
    }

    func testDurationToComponentsOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))
        let toComponentsFQName = durationFQName + [interner.intern("toComponents")]
        let overloads: [(link: String, params: [TypeID])] = [
            ("kk_duration_toComponents_seconds", [sema.types.longType, sema.types.intType]),
            ("kk_duration_toComponents_minutes", [sema.types.longType, sema.types.intType, sema.types.intType]),
            (
                "kk_duration_toComponents_hours",
                [sema.types.longType, sema.types.intType, sema.types.intType, sema.types.intType]
            ),
            (
                "kk_duration_toComponents_days",
                [
                    sema.types.longType,
                    sema.types.intType,
                    sema.types.intType,
                    sema.types.intType,
                    sema.types.intType,
                ]
            ),
        ]

        for overload in overloads {
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toComponentsFQName).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == overload.link
            })
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.receiverType, durationType)
            XCTAssertEqual(signature.parameterTypes.count, 1)
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.returnType, sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0]
            ))))
            XCTAssertTrue(
                sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true,
                "Duration.toComponents should be registered as inline synthetic surface"
            )
            guard let actionType = signature.parameterTypes.first,
                  case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(actionType))
            else {
                return XCTFail("Duration.toComponents action must be a function type")
            }
            XCTAssertEqual(functionType.params, overload.params)
            XCTAssertEqual(functionType.returnType, signature.returnType)
        }
    }

    func testNumericToDurationExtensionsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let durationUnitFQName = ["kotlin", "time", "DurationUnit"].map { interner.intern($0) }
        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationUnitFQName))
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
            let symbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toDurationFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == overload.receiver
                    && signature.parameterTypes == [durationUnitType]
                    && signature.returnType == durationType
            })
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), overload.link)
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            XCTAssertEqual(signature.valueParameterSymbols.count, 1)
            XCTAssertEqual(
                sema.symbols.propertyType(for: signature.valueParameterSymbols[0]),
                durationUnitType
            )
        }
    }
}
