#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

// KUU-3891: the compiler-provided `.static` `E.entries` EnumEntries stub is a
// classifier-scope member, not an instance member. It must stay invisible to
// instance-typed receivers (`E.X.entries`) and to member scope during
// unqualified lookup inside the enum body — where an inherited interface
// `entries` member wins — while remaining reachable through the class-name
// receiver (`E.entries`) and through the enclosing classifier's static scope
// for unqualified references when no instance member shadows it.
@Suite
struct EnumStaticEntriesMemberLookupTests {
    /// Inside the enum body, an unqualified `entries` read is member scope:
    /// the inherited interface instance member wins over the `.static`
    /// synthetic stub (kotlinc: `fun test() = entries` returns `I.entries`).
    @Test func unqualifiedEntriesInEnumBodyPrefersInheritedInterfaceMember() throws {
        try withTemporaryFile(contents: """
        interface I { val entries: String get() = "OK" }
        enum class E : I {
            X;
            fun test() = entries
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                guard case let .nameRef(name, _) = expr, ctx.interner.resolve(name) == "entries" else {
                    return nil
                }
                return ExprID(rawValue: Int32(index))
            }.first)
            let selectedSymbol = try #require(sema.bindings.identifierSymbol(for: reference))
            let interfaceEntries = try #require(sema.symbols.lookup(
                fqName: ["I", "entries"].map(ctx.interner.intern)
            ))

            #expect(selectedSymbol == interfaceEntries)
        }
    }

    /// `E.X.entries` reads through an instance receiver: the `.static` stub
    /// is not a candidate, so the inherited interface member resolves.
    @Test func instanceReceiverEntriesResolvesInterfaceMemberNotStaticStub() throws {
        try withTemporaryFile(contents: """
        interface I { val entries: String get() = "OK" }
        enum class E : I { X }
        fun read() = E.X.entries
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                guard case let .memberCall(_, name, _, _, _) = expr,
                      ctx.interner.resolve(name) == "entries"
                else {
                    return nil
                }
                return ExprID(rawValue: Int32(index))
            }.first)
            let selectedSymbol = try #require(sema.bindings.identifierSymbol(for: reference))
            let interfaceEntries = try #require(sema.symbols.lookup(
                fqName: ["I", "entries"].map(ctx.interner.intern)
            ))

            #expect(selectedSymbol == interfaceEntries)
        }
    }

    /// On a plain enum, an unqualified `entries` inside the body still
    /// resolves through the enclosing classifier's static scope — the same
    /// `EnumEntries` member `E.entries` exposes (kotlinc compiles this).
    @Test func unqualifiedEntriesInPlainEnumBodyResolvesStaticStub() throws {
        try withTemporaryFile(contents: """
        enum class E {
            X;
            fun test() = entries
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                guard case let .nameRef(name, _) = expr, ctx.interner.resolve(name) == "entries" else {
                    return nil
                }
                return ExprID(rawValue: Int32(index))
            }.first)
            let selectedSymbol = try #require(sema.bindings.identifierSymbol(for: reference))
            let selectedInfo = try #require(sema.symbols.symbol(selectedSymbol))
            let enumSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("E")]))

            #expect(selectedInfo.flags.contains(.static),
                    "the unqualified read must resolve the enum class's `.static` entries stub")
            #expect(sema.symbols.parentSymbol(for: selectedSymbol) == enumSymbol)
        }
    }

    /// `E.X.entries` on a plain enum resolves nothing through the instance
    /// receiver — kotlinc reports `unresolved reference 'entries'`.
    @Test func instanceReceiverEntriesOnPlainEnumIsUnresolved() throws {
        try withTemporaryFile(contents: """
        enum class E { X }
        fun read() = E.X.entries
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(ctx.diagnostics.hasError,
                    "an instance-typed receiver must not reach the `.static` entries stub")
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.message.contains("entries")
            })
        }
    }

    /// A user-declared instance `val entries` keeps winning instance lookups
    /// over the synthetic stub (the KUU-3544 coexistence contract).
    @Test func userDeclaredInstanceEntriesStillWinsOverStaticStub() throws {
        try withTemporaryFile(contents: """
        enum class E(val entries: Int) { X(7) }
        fun read() = E.X.entries
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let reference = try #require(ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
                guard case let .memberCall(_, name, _, _, _) = expr,
                      ctx.interner.resolve(name) == "entries"
                else {
                    return nil
                }
                return ExprID(rawValue: Int32(index))
            }.first)
            let selectedSymbol = try #require(sema.bindings.identifierSymbol(for: reference))
            let selectedInfo = try #require(sema.symbols.symbol(selectedSymbol))

            #expect(!selectedInfo.flags.contains(.static))
            #expect(!selectedInfo.flags.contains(.synthetic),
                    "the constructor `val entries` is a user declaration, not the synthetic stub")
        }
    }
}
#endif
