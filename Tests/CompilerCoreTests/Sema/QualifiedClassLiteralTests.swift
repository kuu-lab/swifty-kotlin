@testable import CompilerCore
import Testing

@Suite
struct QualifiedClassLiteralTests {
    @Test(arguments: ["Outer.Nested.Deep", "Sample.deep.Outer.Nested.Deep", "Alias.Nested.Deep", "Middle.Deep"], [false, true])
    func nestedClassifierPathsResolveWithoutConstructingInstances(receiver: String, requiresArguments: Bool) throws {
        let parameters = requiresArguments ? "(val value: Int)" : ""
        let source = """
        package Sample.deep
        import Sample.deep.Outer as Alias
        import Sample.deep.Outer.Nested as Middle
        class Outer { class Nested\(parameters) { class Deep\(parameters) } }
        fun use() = \(receiver)::class
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ref = try #require(firstExprID(in: ast) { _, expr in
                if case .callableRef = expr { return true }
                return false
            })
            let symbol = try #require(sema.symbols.lookup(fqName:
                ["Sample", "deep", "Outer", "Nested", "Deep"].map { ctx.interner.intern($0) }
            ))
            #expect(sema.bindings.classRefTargetType(for: ref) == sema.types.make(.classType(ClassType(classSymbol: symbol))))
            #expect(!sema.bindings.boundClassRefExprs.contains(ref))
            let memberCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                if case .memberCall = expr { return true }
                return false
            }
            #expect(memberCalls.allSatisfy { sema.bindings.callBinding(for: $0) == nil })
        }
    }

    @Test(arguments: ["parameter", "local", "property", "member", "call"])
    func valueReceiversRemainBound(shadow: String) throws {
        let use: String
        switch shadow {
        case "parameter": use = "fun use(Outer: Value) = Outer.Nested.Deep::class"
        case "local": use = "fun use(): Any { val Outer = Value(); return Outer.Nested.Deep::class }"
        case "property": use = "val Outer = Value()\nfun use() = Outer.Nested.Deep::class"
        case "member": use = "class Owner(val Outer: Value) { fun use() = Outer.Nested.Deep::class }"
        default: use = "fun use() = Value().Nested.Deep::class"
        }
        try withTemporaryFiles(contents: [
            "package selected\nclass Outer { class Nested { class Deep } }",
            """
            package consumer
            import selected.Outer
            class Leaf
            class Middle { val Deep: Leaf = Leaf() }
            class Value { val Nested: Middle = Middle() }
            \(use)
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let ref = try #require(firstExprID(in: ast) { _, expr in
                if case .callableRef = expr { return true }
                return false
            })
            let leaf = try #require(sema.symbols.lookup(fqName: ["consumer", "Leaf"].map { ctx.interner.intern($0) }))
            #expect(sema.bindings.classRefTargetType(for: ref) == sema.types.make(.classType(ClassType(classSymbol: leaf))))
            #expect(sema.bindings.boundClassRefExprs.contains(ref))
        }
    }

    @Test
    func privateNestedClassifierIsRejected() throws {
        try withTemporaryFile(contents: "class Outer { class Nested { private class Deep } }\nfun use() = Outer.Nested.Deep::class") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            #expect(ctx.diagnostics.diagnostics.contains { $0.message.contains("Deep") && $0.message.lowercased().contains("private") })
        }
    }
}
