#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ConstructorThisReceiverResolutionTests {
    @Test
    func anonymousObjectSuperArgumentSelectsCompanionReceiver() throws {
        let source = """
        fun WithCompanion.test() {
            object : WithCompanion(this) {}
        }
        open class WithCompanion(a: WithCompanion.Companion) {
            companion object
        }
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let thisIndex = ast.arena.exprs.enumerated().first { entry in
            guard case let .thisRef(label, _) = entry.element else { return false }
            return label == nil
        }?.offset
        let thisExpr = try #require(thisIndex.map { ExprID(rawValue: Int32($0)) })
        let withCompanion = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("WithCompanion")]))
        let companion = try #require(sema.symbols.companionObjectSymbol(for: withCompanion))
        let selectedType = try #require(sema.bindings.exprType(for: thisExpr))

        #expect(sema.bindings.identifierSymbol(for: thisExpr) == companion)
        guard case let .classType(classType) = sema.types.kind(of: selectedType) else {
            Issue.record("Expected the contextual `this` type to be the Companion object.")
            return
        }
        #expect(classType.classSymbol == companion)
    }
}
#endif
