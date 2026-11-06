@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// Regression coverage for KUU-4012: indexed access on a class name
/// (`K[i]`, `Outer.K[i]`) denotes the companion object, so `operator fun
/// get`/`set` declared in the companion scope must resolve exactly like
/// `K.member` reads — never through the class's instance members.
@Suite
struct IndexedAccessClassNameReceiverTests {
    @Test
    func companionObjectGetResolvesThroughClassName() throws {
        let ctx = makeContextFromSource("""
        class K { companion object { operator fun get(i: Int) = "got$i" } }
        fun probe(): String = K[1]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Companion"))
    }

    @Test
    func enumCompanionGetResolvesThroughClassName() throws {
        let ctx = makeContextFromSource("""
        enum class Month { JAN, FEB; companion object { operator fun get(i: Int) = "m$i" } }
        fun probe(): String = Month[0]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Companion"))
    }

    @Test
    func qualifiedClassNameGetResolvesThroughCompanion() throws {
        let ctx = makeContextFromSource("""
        class Outer { class Nested { companion object { operator fun get(i: Int) = i * 2 } } }
        fun probe(): Int = Outer.Nested[3]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let indexed = try #require(firstIndexedAccess(in: ast, ctx: ctx))
        #expect(sema.bindings.callBinding(for: indexed)?.chosenCallee != nil)
    }

    @Test
    func companionGetWinsOverInstanceGet() throws {
        let ctx = makeContextFromSource("""
        class Both {
            operator fun get(i: Int) = "inst$i"
            companion object { operator fun get(i: Int) = "comp$i" }
        }
        fun probe(): String = Both[1]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Companion"))
    }

    @Test
    func instanceGetWithoutCompanionIsRejected() throws {
        let ctx = makeContextFromSource("""
        class Only { operator fun get(i: Int) = "inst$i" }
        fun probe(): String = Only[1]
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" },
                "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func companionSetResolvesThroughClassName() throws {
        let ctx = makeContextFromSource("""
        class Box {
            companion object {
                val items = mutableListOf("a", "b")
                operator fun set(i: Int, v: String) { items[i] = v }
            }
        }
        fun probe() { Box[1] = "z" }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        // The companion body's own `items[i] = v` is also an indexedAssign;
        // pick the one whose receiver is the `Box` class name.
        let boxName = ctx.interner.intern("Box")
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedAssign(receiver, _, _, range) = expr,
                  case let .nameRef(name, _) = ast.arena.expr(receiver),
                  name == boxName,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return false }
            return true
        })
        let callee = try #require(sema.bindings.callBinding(for: assignment)?.chosenCallee)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Companion"))
    }

    @Test
    func companionCompoundAssignResolvesGetAndSet() throws {
        let ctx = makeContextFromSource("""
        class Counter {
            companion object {
                var value = 0
                operator fun get(i: Int) = value
                operator fun set(i: Int, v: Int) { value = v }
            }
        }
        fun probe() { Counter[0] += 2 }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .indexedCompoundAssign(_, _, _, _, range) = expr else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        })
        let binding = try #require(sema.bindings.indexedCompoundAssignOperatorBinding(for: assignment))
        let owner = try #require(sema.symbols.parentSymbol(for: binding.setCall.chosenCallee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("Companion"))
    }

    @Test
    func companionBlockGetResolvesThroughClassName() throws {
        let ctx = makeContextFromSource("""
        class Host { companion { operator fun get(i: Int) = "b$i" } }
        fun probe(): String = Host[7]
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let (sema, callee) = try indexedCallee(in: ctx)
        let owner = try #require(sema.symbols.parentSymbol(for: callee))
        #expect(sema.symbols.symbol(owner)?.name == ctx.interner.intern("$CompanionBlocks"))
    }

    @Test
    func localValueShadowingClassNameKeepsInstanceLookup() throws {
        let ctx = makeContextFromSource("""
        class Slots { operator fun get(i: Int) = i }
        fun probe(slots: Slots): Int {
            val Slots = listOf(4, 5, 6)
            return Slots[1]
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    private func firstIndexedAccess(in ast: ASTModule, ctx: CompilationContext) -> ExprID? {
        firstExprID(in: ast) { _, expr in
            guard case let .indexedAccess(_, _, range) = expr else { return false }
            return ctx.sourceManager.origin(of: range.start.file) == .user
        }
    }

    private func indexedCallee(in ctx: CompilationContext) throws -> (SemaModule, SymbolID) {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let indexed = try #require(firstIndexedAccess(in: ast, ctx: ctx))
        let callee = try #require(sema.bindings.callBinding(for: indexed)?.chosenCallee)
        return (sema, callee)
    }
}
