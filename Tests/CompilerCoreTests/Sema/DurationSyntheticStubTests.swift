@testable import CompilerCore
import XCTest

final class DurationSyntheticStubTests: XCTestCase {
    func testDurationOperatorMembersAreRegisteredWithReceiverType() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let expectedMembers: [(name: String, link: String, parameterTypes: [TypeID])] = [
            ("plus", "kk_duration_plus", [durationType]),
            ("minus", "kk_duration_minus", [durationType]),
            ("times", "kk_duration_times_int", [sema.types.intType]),
            ("div", "kk_duration_div_int", [sema.types.intType]),
            ("div", "kk_duration_div_duration", [durationType]),
            ("compareTo", "kk_duration_compareTo", [durationType]),
            ("unaryMinus", "kk_duration_unary_minus", []),
        ]

        for member in expectedMembers {
            let memberFQName = durationFQName + [interner.intern(member.name)]
            let matchingSymbols = sema.symbols.lookupAll(fqName: memberFQName).filter { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == durationType
                    && signature.parameterTypes == member.parameterTypes
            }

            XCTAssertEqual(
                matchingSymbols.count,
                1,
                "Expected exactly one Duration.\(member.name) overload with receiverType=Duration"
            )
            let symbol = try XCTUnwrap(matchingSymbols.first)
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .function)
            XCTAssertTrue(
                sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true,
                "Duration.\(member.name) should be an operatorFunction"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), member.link)
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

        // MIGRATION-TIME-002: toIsoString is now a Kotlin-source extension function at
        // package scope ["kotlin","time","toIsoString"], not a synthetic stub member.
        let toIsoPackageFQName = ["kotlin", "time", "toIsoString"].map { interner.intern($0) }
        let toIsoSymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: toIsoPackageFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == durationType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        }, "Duration.toIsoString should be present as a Kotlin-source extension (MIGRATION-TIME-002)")
        XCTAssertNil(
            sema.symbols.externalLinkName(for: toIsoSymbol),
            "Duration.toIsoString should be a bundled Kotlin function with no C external link (MIGRATION-TIME-002)"
        )
        XCTAssertNotNil(
            sema.symbols.symbol(toIsoSymbol)?.declSite,
            "Duration.toIsoString should have a declSite (Kotlin source, not a synthetic stub)"
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
            XCTAssertFalse(
                sema.symbols.lookupAll(fqName: oldToComponentsFQName).contains { symbolID in
                    sema.symbols.externalLinkName(for: symbolID) == linkName
                },
                "Duration.toComponents should no longer have C stub '\(linkName)' (MIGRATION-TIME-002)"
            )
        }

        let toComponentsFQName = ["kotlin", "time", "toComponents"].map { interner.intern($0) }
        let expectedLambdaArities = [2, 3, 4, 5]
        for expectedArity in expectedLambdaArities {
            let symbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: toComponentsFQName).first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID),
                          sig.receiverType == durationType,
                          sig.parameterTypes.count == 1,
                          case let .functionType(ft) = sema.types.kind(
                              of: sema.types.makeNonNullable(sig.parameterTypes[0]))
                    else { return false }
                    return ft.params.count == expectedArity
                },
                "Missing toComponents overload with lambda arity \(expectedArity) (MIGRATION-TIME-002)"
            )
            XCTAssertNotNil(
                sema.symbols.symbol(symbol)?.declSite,
                "Duration.toComponents (arity \(expectedArity)) should have a declSite (Kotlin source)"
            )
            XCTAssertNil(
                sema.symbols.externalLinkName(for: symbol),
                "Duration.toComponents (arity \(expectedArity)) should have no C external link"
            )
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
