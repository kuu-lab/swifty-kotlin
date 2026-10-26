#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct SuperInterfacePropertyResolutionTests {
    @Test func resolvesUnqualifiedSuperPropertyAndKeepsFunctionLookupDistinct() throws {
        let source = """
        interface Deep {
            val label: String get() = "OK"
        }
        interface DeepFunction {
            fun label(): String = "FUNCTION"
        }
        class Leaf : Deep, DeepFunction {
            fun readProperty(): String = super.label
            fun readFunction(): String = super.label()
            fun readThisProperty(): String = this.label
        }
        """
        let ctx = try semaContext(for: [source])
        #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: ["Deep", "label"].map(ctx.interner.intern)))
        let function = try #require(sema.symbols.lookup(fqName: ["DeepFunction", "label"].map(ctx.interner.intern)))
        let memberCalls = memberCallExprIDs(named: "label", in: ast, interner: ctx.interner)
        let superProperty = try #require(memberCalls.first { id in
            guard !ast.arena.isExplicitCall(id),
                  case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(id)
            else { return false }
            return if case .superRef = ast.arena.expr(receiver) { true } else { false }
        })
        let superFunction = try #require(memberCalls.first { id in
            guard ast.arena.isExplicitCall(id),
                  case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(id)
            else { return false }
            return if case .superRef = ast.arena.expr(receiver) { true } else { false }
        })
        let thisProperty = try #require(memberCalls.first { id in
            guard !ast.arena.isExplicitCall(id),
                  case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(id)
            else { return false }
            return if case .thisRef = ast.arena.expr(receiver) { true } else { false }
        })
        #expect(sema.bindings.identifierSymbol(for: superProperty) == property)
        #expect(sema.bindings.callBinding(for: superFunction)?.chosenCallee == function)
        #expect(sema.bindings.identifierSymbol(for: thisProperty) == property)
    }

    @Test func rejectsAmbiguousUnqualifiedSuperProperties() throws {
        let ctx = try semaContext(for: ["""
        interface Left { val label: String get() = "LEFT" }
        interface Right { val label: String get() = "RIGHT" }
        class Both : Left, Right {
            override val label: String get() = "BOTH"
            fun read(): String = super.label
        }
        """])
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Unexpected diagnostics: \(errors.map(\.message))")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0056")
        #expect(errors.first?.message.contains("super<Foo>") == true)
    }
}
#endif
