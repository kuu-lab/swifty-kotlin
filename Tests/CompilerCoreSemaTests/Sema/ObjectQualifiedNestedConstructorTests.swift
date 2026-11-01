@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ObjectQualifiedNestedConstructorTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [
        "object Holder { class Child }; fun result() = Holder.Child()",
        "class Holder { class Child }; fun result() = Holder.Child()",
        "object Holder { class Child(val n: Int) }; fun result() = Holder.Child(7)",
        "object Holder { class Child(val n: Int = 7) }; fun result() = Holder.Child()",
        "object Outer { object Holder { class Child } }; fun result() = Outer.Holder.Child()",
        "import Holder as Alias; object Holder { class Child }; fun result() = Alias.Child()",
    ])
    func qualifierSelectsNestedConstructor(source: String) throws {
        let ctx = context(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "Child", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        #expect(sema.bindings.isTypeQualifiedConstructorCallExpr(call))
        let owner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
        #expect(sema.bindings.exprType(for: call) == sema.types.make(.classType(ClassType(
            classSymbol: owner, args: [], nullability: .nonNull
        ))))
    }

    @Test func ordinaryObjectMemberKeepsInstanceReceiver() throws {
        let ctx = context("""
        object Holder { val n: Int = 7; fun child(): Int = n; class Child }
        fun result(): Int = Holder.child()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "child", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .function)
        #expect(!sema.bindings.isTypeQualifiedConstructorCallExpr(call))
    }

    @Test(arguments: [
        "class Child(val n: String); fun Child(n: Int): Int = 42",
        "class Child private constructor(val n: Number); fun Child(n: Int): Int = 42",
    ])
    func inapplicableConstructorYieldsToObjectFactory(members: String) throws {
        let ctx = context("object Holder { \(members) }; fun result(): Int = Holder.Child(7)")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "Child", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .function)
        #expect(sema.bindings.exprType(for: call) == sema.types.intType)
        #expect(!sema.bindings.isTypeQualifiedConstructorCallExpr(call))
    }

    @Test(arguments: [
        ("object Holder { private class Child }; fun result() = Holder.Child()", "KSWIFTK-SEMA-0040"),
        ("object Holder { class Child private constructor() }; fun result() = Holder.Child()", "KSWIFTK-SEMA-0040"),
        ("object Holder { class Child(val n: Int) }; fun result() = Holder.Child(\"bad\")", "KSWIFTK-SEMA-0473"),
        ("object Holder { class Child(val n: Int) }; fun result() = Holder.Child()", "KSWIFTK-SEMA-0002"),
        ("object Holder { class Child }; fun result() { val holder = Holder; holder.Child() }", "KSWIFTK-SEMA-0024"),
        ("object Holder { class Child }; fun result() = Holder?.Child()", "KSWIFTK-SEMA-0024"),
        ("object Holder { class Child; fun result() = this.Child() }", "KSWIFTK-SEMA-0024"),
        ("class Holder { class Child }; fun result() = Holder().Child()", "KSWIFTK-SEMA-0024"),
    ])
    func invalidCallsRemainRejected(source: String, diagnostic: String) throws {
        let ctx = context(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error && $0.code == diagnostic },
                "\(ctx.diagnostics.diagnostics)")
    }
}
