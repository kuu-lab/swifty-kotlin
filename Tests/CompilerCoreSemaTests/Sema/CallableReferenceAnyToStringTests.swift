#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableReferenceAnyToStringTests {
    @Test func boundAnyToStringReferenceInfersZeroArgumentFunction() throws {
        let ctx = makeContextFromSource("""
        annotation class Ann(val value: Int)

        fun main() {
            val a: Any = Ann(1)
            val bound = a::toString
            val unbound: (Any) -> String = Any::toString
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let inputPath = try #require(ctx.options.inputs.first)
        let inputFileID = try #require(ctx.sourceManager.fileID(forPath: inputPath))
        let callableReferences = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case .callableRef = expr,
                  ast.arena.exprRange(exprID)?.start.file == inputFileID
            else { return nil }
            return exprID
        }
        try #require(callableReferences.count == 2)

        let boundReference = callableReferences[0]
        let boundExprType = try #require(sema.bindings.exprType(for: boundReference))
        guard case let .functionType(boundType) = sema.types.kind(of: boundExprType) else {
            Issue.record("Expected a function type for the bound Any::toString reference.")
            return
        }
        #expect(boundType.params.isEmpty)
        #expect(boundType.returnType == sema.types.stringType)
        #expect(!sema.bindings.isUnboundCallableRef(boundReference))
        let expectedTarget = ["kotlin", "Any", "toString"]
        let boundTarget = try #require(sema.bindings.identifierSymbol(for: boundReference))
        #expect(sema.symbols.symbol(boundTarget)?.fqName.map { ctx.interner.resolve($0) } == expectedTarget)

        let unboundReference = callableReferences[1]
        let unboundExprType = try #require(sema.bindings.exprType(for: unboundReference))
        guard case let .functionType(unboundType) = sema.types.kind(of: unboundExprType) else {
            Issue.record("Expected a function type for the unbound Any::toString reference.")
            return
        }
        #expect(unboundType.params == [sema.types.anyType])
        #expect(unboundType.returnType == sema.types.stringType)
        #expect(sema.bindings.isUnboundCallableRef(unboundReference))
        let unboundTarget = try #require(sema.bindings.identifierSymbol(for: unboundReference))
        #expect(sema.symbols.symbol(unboundTarget)?.fqName.map { ctx.interner.resolve($0) } == expectedTarget)
    }
}
#endif
