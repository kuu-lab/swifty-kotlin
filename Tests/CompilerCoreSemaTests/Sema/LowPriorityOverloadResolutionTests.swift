#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension OverloadResolverTests {
    @Test func testLowPriorityCandidateYieldsToLessSpecificRegularCandidate() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType
        let stringType = types.stringType

        let lowPriority = defineSymbol(
            kind: .function,
            name: "priority",
            suffix: "lowPrioritySpecific",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: stringType),
            for: lowPriority
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.internal.LowPriorityInOverloadResolution")],
            for: lowPriority
        )

        let regularPriority = defineSymbol(
            kind: .function,
            name: "priority",
            suffix: "regularPriorityGeneral",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyType], returnType: stringType),
            for: regularPriority
        )

        let resolved = resolver.resolveCall(
            candidates: [lowPriority, regularPriority],
            call: CallExpr(
                range: makeRange(start: 700, end: 710),
                calleeName: interner.intern("priority"),
                args: [CallArg(type: intType)]
            ),
            expectedType: nil,
            ctx: ctx
        )

        #expect(resolved.chosenCallee == regularPriority)
        #expect(resolved.diagnostic == nil)
    }

    @Test func testSamePriorityCandidatesRemainAmbiguousAfterLowerPriorityCandidateIsRemoved() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let anyType = types.anyType

        func makeCandidate(_ suffix: String, parameterType: TypeID) -> SymbolID {
            let candidate = defineSymbol(
                kind: .function,
                name: "ambiguousPriority",
                suffix: suffix,
                symbols: symbols,
                interner: interner
            )
            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [parameterType], returnType: intType),
                for: candidate
            )
            return candidate
        }

        let firstRegular = makeCandidate("firstRegular", parameterType: intType)
        let secondRegular = makeCandidate("secondRegular", parameterType: intType)
        let lowPriority = makeCandidate("lowPriority", parameterType: anyType)
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.internal.LowPriorityInOverloadResolution")],
            for: lowPriority
        )

        let resolved = resolver.resolveCall(
            candidates: [firstRegular, secondRegular, lowPriority],
            call: CallExpr(
                range: makeRange(start: 711, end: 724),
                calleeName: interner.intern("ambiguousPriority"),
                args: [CallArg(type: intType)]
            ),
            expectedType: nil,
            ctx: ctx
        )

        #expect(resolved.chosenCallee == nil)
        #expect(resolved.diagnostic?.code == "KSWIFTK-SEMA-0003")
    }

    @Test func testInapplicableLowPriorityCandidateDoesNotAffectRegularCandidate() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let booleanType = types.make(.primitive(.boolean, .nonNull))
        let anyType = types.anyType

        let lowPriority = defineSymbol(
            kind: .function,
            name: "inapplicableLowPriority",
            suffix: "lowPriorityBoolean",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [booleanType], returnType: intType),
            for: lowPriority
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.internal.LowPriorityInOverloadResolution")],
            for: lowPriority
        )

        let regularPriority = defineSymbol(
            kind: .function,
            name: "inapplicableLowPriority",
            suffix: "regularPriorityAny",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyType], returnType: intType),
            for: regularPriority
        )

        let resolved = resolver.resolveCall(
            candidates: [lowPriority, regularPriority],
            call: CallExpr(
                range: makeRange(start: 725, end: 742),
                calleeName: interner.intern("inapplicableLowPriority"),
                args: [CallArg(type: intType)]
            ),
            expectedType: nil,
            ctx: ctx
        )

        #expect(resolved.chosenCallee == regularPriority)
        #expect(resolved.diagnostic == nil)
    }

    @Test func testLowPriorityCandidateRemainsWhenRegularPriorityCandidatesAreInapplicable() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()
        let intType = types.make(.primitive(.int, .nonNull))
        let booleanType = types.make(.primitive(.boolean, .nonNull))

        let lowPriority = defineSymbol(
            kind: .function,
            name: "onlyApplicablePriority",
            suffix: "lowPriorityInt",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: lowPriority
        )
        symbols.setAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.internal.LowPriorityInOverloadResolution")],
            for: lowPriority
        )

        let regularPriority = defineSymbol(
            kind: .function,
            name: "onlyApplicablePriority",
            suffix: "regularPriorityBoolean",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [booleanType], returnType: intType),
            for: regularPriority
        )

        let resolved = resolver.resolveCall(
            candidates: [lowPriority, regularPriority],
            call: CallExpr(
                range: makeRange(start: 743, end: 761),
                calleeName: interner.intern("onlyApplicablePriority"),
                args: [CallArg(type: intType)]
            ),
            expectedType: nil,
            ctx: ctx
        )

        #expect(resolved.chosenCallee == lowPriority)
        #expect(resolved.diagnostic == nil)
    }
}
#endif
