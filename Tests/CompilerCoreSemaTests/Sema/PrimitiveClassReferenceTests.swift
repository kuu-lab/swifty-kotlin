@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveClassReferenceTests {
    @Test(arguments: ["Int", "kotlin.Int", "ImportedInt"])
    func primitiveClassifierUsesCanonicalKClassArgument(receiver: String) throws {
        try withTemporaryFile(contents:
            "package consumer\nimport kotlin.Int as ImportedInt\nfun literal() = \(receiver)::class"
        ) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ref = try #require(firstExprID(in: ast) { _, expr in
                if case .callableRef = expr { return true }
                return false
            })
            let type = try #require(sema.bindings.exprType(for: ref))
            guard case let .kClassType(klass) = sema.types.kind(of: type) else {
                Issue.record("Expected a KClass type")
                return
            }
            #expect(klass.argument == sema.types.intType)
            let target = try #require(sema.bindings.classRefTargetType(for: ref))
            let symbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "Int"].map(ctx.interner.intern)))
            #expect(target == sema.types.make(.classType(ClassType(classSymbol: symbol))))
            #expect(!sema.bindings.boundClassRefExprs.contains(ref))
        }
    }

    @Test(arguments: ["Int", "consumer.Int", "UserInt"])
    func userClassifierWithPrimitiveNameRemainsNominal(receiver: String) throws {
        try withTemporaryFile(contents: """
        package consumer
        import consumer.Int as UserInt
        class Int
        fun literal() = \(receiver)::class
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ref = try #require(firstExprID(in: ast) { _, expr in
                if case .callableRef = expr { return true }
                return false
            })
            let type = try #require(sema.bindings.exprType(for: ref))
            guard case let .kClassType(klass) = sema.types.kind(of: type) else {
                Issue.record("Expected a KClass type")
                return
            }
            let symbol = try #require(sema.symbols.lookup(fqName: ["consumer", "Int"].map(ctx.interner.intern)))
            #expect(klass.argument == sema.types.make(.classType(ClassType(classSymbol: symbol))))
            #expect(!sema.bindings.boundClassRefExprs.contains(ref))
        }
    }
}
