#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EnumCompanionCallableReferenceTests {
    @Test
    func enumValueOfBindsTheCompanionImplicitlyAndPreservesOtherReceiverShapes() throws {
        let source = """
        enum class E {
            ENTRY;
            fun label(): String = "entry"
        }

        enum class Shadowed {
            ENTRY;
            companion object {
                fun valueOf(name: String): Shadowed = ENTRY
            }
        }

        class Plain(val value: Int) {
            companion object {
                fun from(value: Int): Plain = Plain(value)
            }
        }

        fun probe() {
            val fromName: (String) -> E = E::valueOf
            val label: (E) -> String = E::label
            val custom: (String) -> Shadowed = Shadowed::valueOf
            val explicitCompanion: (String) -> Shadowed = Shadowed.Companion::valueOf
            val ordinaryCompanion: (Int) -> Plain = Plain.Companion::from
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard case .callableRef? = ast.arena.expr(exprID) else { return nil }
                return exprID
            }
            try #require(references.count == 5)

            let enumType = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("E")]))
            let shadowedType = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Shadowed")]))
            let plainType = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Plain")]))
            let enumValueOf = references[0]
            let enumLabel = references[1]
            let shadowedValueOf = references[2]
            let explicitCompanionValueOf = references[3]
            let plainCompanionFrom = references[4]

            let enumValueOfType = try functionType(of: enumValueOf, sema: sema)
            #expect(enumValueOfType.params == [sema.types.stringType])
            #expect(enumValueOfType.returnType == sema.types.make(.classType(ClassType(
                classSymbol: enumType,
                args: [],
                nullability: .nonNull
            ))))
            #expect(!sema.bindings.isUnboundCallableRef(enumValueOf))
            let enumValueOfTarget = try #require(sema.bindings.identifierSymbol(for: enumValueOf))
            #expect(sema.symbols.parentSymbol(for: enumValueOfTarget) == sema.symbols.companionObjectSymbol(for: enumType))

            let enumLabelType = try functionType(of: enumLabel, sema: sema)
            #expect(enumLabelType.params.count == 1)
            #expect(enumLabelType.returnType == sema.types.stringType)
            #expect(sema.bindings.isUnboundCallableRef(enumLabel))

            let shadowedValueOfType = try functionType(of: shadowedValueOf, sema: sema)
            #expect(shadowedValueOfType.params == [sema.types.stringType])
            #expect(shadowedValueOfType.returnType == sema.types.make(.classType(ClassType(
                classSymbol: shadowedType,
                args: [],
                nullability: .nonNull
            ))))
            #expect(!sema.bindings.isUnboundCallableRef(shadowedValueOf))

            let explicitCompanionType = try functionType(of: explicitCompanionValueOf, sema: sema)
            #expect(explicitCompanionType.params == [sema.types.stringType])
            #expect(!sema.bindings.isUnboundCallableRef(explicitCompanionValueOf))

            let plainCompanionType = try functionType(of: plainCompanionFrom, sema: sema)
            #expect(plainCompanionType.params == [sema.types.make(.primitive(.int, .nonNull))])
            #expect(plainCompanionType.returnType == sema.types.make(.classType(ClassType(
                classSymbol: plainType,
                args: [],
                nullability: .nonNull
            ))))
            #expect(!sema.bindings.isUnboundCallableRef(plainCompanionFrom))
        }
    }

    private func functionType(of expression: ExprID, sema: SemaModule) throws -> FunctionType {
        let type = try #require(sema.bindings.exprType(for: expression))
        guard case let .functionType(functionType) = sema.types.kind(of: type) else {
            Issue.record("Expected a callable reference function type.")
            throw TestFailure.expectedFunctionType
        }
        return functionType
    }
}

private enum TestFailure: Error {
    case expectedFunctionType
}
#endif
