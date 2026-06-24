#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct DurationSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testDurationOperatorMembersAreRegisteredWithReceiverType() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
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

            #expect(
                matchingSymbols.count == 1,
                "Expected exactly one Duration.\(member.name) overload with receiverType=Duration"
            )
            let symbol = try #require(matchingSymbols.first)
            #expect(sema.symbols.symbol(symbol)?.kind == .function)
            #expect(
                sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true,
                "Duration.\(member.name) should be an operatorFunction"
            )
            #expect(sema.symbols.externalLinkName(for: symbol) == member.link)
        }
    }

    @Test func testDurationIsoAndParseSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
        let durationType = sema.types.make(.classType(ClassType(
            classSymbol: durationSymbol,
            args: [],
            nullability: .nonNull
        )))

        let toIsoFQName = durationFQName + [interner.intern("toIsoString")]
        let toIsoSymbol = try #require(sema.symbols.lookupAll(fqName: toIsoFQName).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == durationType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.stringType
        })
        #expect(sema.symbols.externalLinkName(for: toIsoSymbol) == "kk_duration_toIsoString")
        #expect(
            !(sema.symbols.symbol(toIsoSymbol)?.flags.contains(.operatorFunction) == true),
            "Duration.toIsoString should not be registered as an operator"
        )

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
        #expect(
            sema.symbols.symbol(parseSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parse should use the thrown channel for invalid input"
        )

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
        #expect(
            sema.symbols.symbol(parseIsoSymbol)?.flags.contains(.throwingFunction) == true,
            "Duration.parseIsoString should use the thrown channel for invalid input"
        )

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

    @Test func testDurationToComponentsOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationFQName = ["kotlin", "time", "Duration"].map { interner.intern($0) }
        let durationSymbol = try #require(sema.symbols.lookup(fqName: durationFQName))
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
            let symbol = try #require(sema.symbols.lookupAll(fqName: toComponentsFQName).first { symbolID in
                sema.symbols.externalLinkName(for: symbolID) == overload.link
            })
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.receiverType == durationType)
            #expect(signature.parameterTypes.count == 1)
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.returnType == sema.types.make(.typeParam(TypeParamType(
                symbol: signature.typeParameterSymbols[0]
            ))))
            #expect(
                sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true,
                "Duration.toComponents should be registered as inline synthetic surface"
            )
            guard let actionType = signature.parameterTypes.first,
                  case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(actionType))
            else {
                Issue.record("Duration.toComponents action must be a function type"); return
            }
            #expect(functionType.params == overload.params)
            #expect(functionType.returnType == signature.returnType)
        }
    }

    @Test func testNumericToDurationExtensionsAreRegistered() throws {
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
            #expect(
                sema.symbols.propertyType(for: signature.valueParameterSymbols[0]) == durationUnitType
            )
        }
    }
}
#endif
