@testable import CompilerCore
import Testing

@Suite
struct NestedClassReferenceTests {
    @Test(arguments: ["", "companion object", "companion object Named"], ["Outer", "sample.Outer"])
    func nestedClassifierIsNotABoundClassReference(companion: String, qualifier: String) throws {
        let source = """
        package sample
        class Outer { class Nested { class Deep }; \(companion) }
        fun main() {
            val nested = \(qualifier).Nested::class
            val deep = \(qualifier).Nested.Deep::class
            val instance = \(qualifier).Nested()::class
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let refs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard isUserSourceExpr(id, in: ctx),
                      case let .callableRef(_, member, _) = ast.arena.expr(id),
                      ctx.interner.resolve(member) == "class" else { return nil }
                return id
            }
            #expect(refs.count == 3)
            for ref in refs {
                guard case let .callableRef(receiver?, _, _) = ast.arena.expr(ref),
                      case let .memberCall(_, name, _, _, _) = ast.arena.expr(receiver) else {
                    Issue.record("Expected a qualified class reference")
                    continue
                }
                let expectedPath = ctx.interner.resolve(name) == "Deep"
                    ? ["sample", "Outer", "Nested", "Deep"] : ["sample", "Outer", "Nested"]
                let symbol = try #require(sema.symbols.lookup(fqName: expectedPath.map(ctx.interner.intern)))
                let target = try #require(sema.bindings.classRefTargetType(for: ref))
                #expect(target == sema.types.make(.classType(ClassType(classSymbol: symbol))))
                #expect(sema.bindings.boundClassRefExprs.contains(ref) == ast.arena.isExplicitCall(receiver))
                if !ast.arena.isExplicitCall(receiver) {
                    #expect(sema.bindings.identifierSymbol(for: receiver) == symbol)
                    #expect(sema.bindings.callBinding(for: receiver) == nil)
                }
            }
        }
    }

    @Test(arguments: ["class Nested(val value: Int)", "class Nested private constructor()"])
    func classLiteralDoesNotRequireAnAccessibleZeroArgumentConstructor(declaration: String) throws {
        try withTemporaryFile(contents: """
        class Outer { \(declaration); companion object }
        fun literal() = Outer.Nested::class
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func privateNestedClassifierRemainsInaccessible() throws {
        try withTemporaryFile(contents: """
        class Outer { private class Nested; companion object }
        fun literal() = Outer.Nested::class
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
