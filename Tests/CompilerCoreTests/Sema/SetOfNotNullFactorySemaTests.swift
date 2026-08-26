@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SetOfNotNullFactorySemaTests {
    @Test func testSetFactoryOverloadsResolveToBundledSource() throws {
        let source = """
        fun probe() {
            val singleton = setOf(1)
            val nullableSingleton = setOfNotNull("a")
            val values = setOfNotNull("a", null, "b")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected set factory overloads to type-check, got: \(errors)")

            let sema = try #require(ctx.sema)
            for name in ["setOf", "setOfNotNull"] {
                let symbols = sema.symbols.lookupAll(fqName: ["kotlin", "collections", name].map(ctx.interner.intern))
                #expect(
                    symbols.contains { sema.symbols.isSourceBackedSymbol($0) },
                    "Expected \(name) to have a bundled source declaration, got: \(symbols)"
                )
            }

            let setOfSymbols = sema.symbols.lookupAll(fqName: ["kotlin", "collections", "setOf"].map(ctx.interner.intern))
            let setOfElement = try #require(setOfSymbols.first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                return signature.parameterTypes.count == 1 && signature.valueParameterIsVararg == [false]
            })
            let setOfElementSignature = try #require(sema.symbols.functionSignature(for: setOfElement))
            #expect(setOfElementSignature.returnType != .invalid)
            #expect(sema.symbols.isSourceBackedSymbol(setOfElement))
        }
    }

    @Test func testSetOfNotNullInfersNonNullSetElementType() throws {
        let source = """
        fun probe() {
            val values = setOfNotNull("a", null, "b")
            val explicit: Set<String> = setOfNotNull<String>(null, "c")
            val onlyNull = setOfNotNull(null)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "setOfNotNull"
            }, "Expected setOfNotNull call in AST")

            #expect(
                sema.bindings.isCollectionExpr(callExpr),
                "Expected setOfNotNull to be marked as a collection expression"
            )

            let type = try #require(sema.bindings.exprType(for: callExpr))
            guard case let .classType(classType) = sema.types.kind(of: type) else {
                Issue.record("Expected setOfNotNull to infer Set<String>, got \(sema.types.kind(of: type))")
                return
            }
            let symbol = try #require(sema.symbols.symbol(classType.classSymbol))
            #expect(ctx.interner.resolve(symbol.name) == "Set")
            #expect(classType.args.count == 1)
            guard case let .out(elementType) = classType.args[0] else {
                Issue.record("Expected Set element type to use an out projection")
                return
            }
            #expect(elementType == sema.types.stringType)
        }
    }
}
