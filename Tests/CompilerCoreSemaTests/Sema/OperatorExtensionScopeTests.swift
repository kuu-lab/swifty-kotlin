@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct OperatorExtensionScopeTests {
    @Test(arguments: [false, true])
    func unrelatedReceiverFallsThroughToDefaultImportedMapOperator(useArtifact: Bool) throws {
        try withTemporaryFile(contents: """
        class Counter
        operator fun Counter.plusAssign(value: Int) {}
        fun main() {
            val scope = mutableMapOf<String, Boolean>()
            scope += "x" to true
            println(scope["x"])
        }
        """) { path in
            if useArtifact { TestStdlibCache.shared.prepare() }
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            try requireNoErrors(ctx)
            let (sema, callee) = try compoundAssignmentCallee(in: ctx)
            let symbol = try #require(sema.symbols.symbol(callee))
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "plusAssign"])
            if !useArtifact {
                #expect(sema.symbols.isSourceBackedSymbol(callee))
                #expect(!symbol.flags.contains(.synthetic))
            }
        }
    }

    @Test(arguments: [false, true])
    func applicableUserExtensionKeepsPriority(useArtifact: Bool) throws {
        try withTemporaryFile(contents: """
        operator fun MutableMap<String, Boolean>.plusAssign(value: Pair<String, Boolean>) {
            put(value.first, value.second)
        }
        fun main() {
            val scope = mutableMapOf<String, Boolean>()
            scope += "x" to true
        }
        """) { path in
            if useArtifact { TestStdlibCache.shared.prepare() }
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            try requireNoErrors(ctx)
            let (sema, callee) = try compoundAssignmentCallee(in: ctx)
            let file = try #require(sema.symbols.sourceFileID(for: callee))
            #expect(ctx.sourceManager.origin(of: file) == .user)
        }
    }

    @Test
    func memberOperatorKeepsPriorityOverExtension() throws {
        let ctx = makeContextFromSource("""
        class Counter { operator fun plusAssign(value: Int) {} }
        operator fun Counter.plusAssign(value: Int) {}
        fun main() { val scope = Counter(); scope += 1 }
        """)
        try runSema(ctx)
        try requireNoErrors(ctx)
        let (sema, callee) = try compoundAssignmentCallee(in: ctx)
        let symbol = try #require(sema.symbols.symbol(callee))
        #expect(symbol.fqName.map(ctx.interner.resolve) == ["Counter", "plusAssign"])
    }

    @Test
    func unrelatedLocalExtensionFallsThroughToPackageBeforeDefaultImport() throws {
        let ctx = makeContextFromSource("""
        class Counter
        operator fun MutableMap<String, Boolean>.plusAssign(value: Pair<String, Boolean>) {
            put(value.first, value.second)
        }
        fun main() {
            operator fun Counter.plusAssign(value: Int) {}
            val scope = mutableMapOf<String, Boolean>()
            scope += "x" to true
        }
        """)
        try runSema(ctx)
        try requireNoErrors(ctx)
        let (sema, callee) = try compoundAssignmentCallee(in: ctx)
        let symbol = try #require(sema.symbols.symbol(callee))
        #expect(symbol.fqName.map(ctx.interner.resolve) == ["plusAssign"])
    }

    @Test(arguments: [
        "fun Counter.plusAssign(value: Int) {}",
        "operator fun Counter.plusAssign(value: Int): Int = value",
        "operator fun Counter.plus(value: Int): Counter = this",
        "operator fun Counter.plus(value: Int): String = \"wrong\"",
    ])
    func invalidAssignmentRemainsRejected(declaration: String) throws {
        let ctx = makeContextFromSource("""
        class Counter
        \(declaration)
        fun main() { val scope = Counter(); scope += 1 }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected invalid compound assignment to be rejected")
    }

    @Test
    func extensionWithoutImportIsNotRecoveredByShortName() throws {
        try withTemporaryFiles(contents: [
            "package other; operator fun MutableMap<String, Boolean>.plusAssign(value: Int) {}",
            """
            class Counter
            operator fun Counter.plusAssign(value: Int) {}
            fun main() { val scope = mutableMapOf<String, Boolean>(); scope += 1 }
            """,
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .executable, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "An unimported extension must not become an operator candidate")
        }
    }

    @Test(arguments: [false, true])
    func inapplicableUserPlusExtensionFallsThroughToBundledStdlib(useArtifact: Bool) throws {
        // KUU-4462: a file-level `List<M>.plus(module: M)` extension rejects a
        // `List<M>` argument, so `list + list` must keep resolving to the
        // bundled `Iterable.plus(elements:)` overloads instead of failing
        // with an argument mismatch.
        try withTemporaryFile(contents: """
        class M(val name: String) {
            operator fun plus(modules: List<M>) = listOf(this) + modules
        }
        operator fun List<M>.plus(module: M): List<M> = this + listOf(module)
        fun main() {
            val ms = listOf(M("a"))
            val merged = ms + listOf(M("b"))
            println(merged.map { it.name })
        }
        """) { path in
            if useArtifact { TestStdlibCache.shared.prepare() }
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable, allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            try requireNoErrors(ctx)
            let sema = try #require(ctx.sema)
            for exprID in userBinaryPlusExprIDs(in: ctx) {
                let callee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(callee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "plus"])
            }
        }
    }

    @Test
    func applicableUserPlusExtensionKeepsPriorityOverStdlib() throws {
        let ctx = makeContextFromSource("""
        class M(val name: String)
        operator fun List<M>.plus(module: M): List<M> = this + listOf(module)
        fun main() {
            val ms = listOf(M("a"))
            val single = ms + M("b")
            println(single.map { it.name })
        }
        """)
        try runSema(ctx)
        try requireNoErrors(ctx)
        let sema = try #require(ctx.sema)
        // `ms + M("b")` is the only `+` whose RHS is not a `listOf` call: the
        // user extension is applicable there and must win over the bundled
        // `plus(element:)` overload.
        let elementPlus = try #require(userBinaryPlusExprIDs(in: ctx).first { exprID in
            guard let ast = ctx.ast,
                  let binaryExpr = ast.arena.expr(exprID),
                  case let .binary(_, _, rhs, _) = binaryExpr,
                  let rhsExpr = ast.arena.expr(rhs),
                  case let .call(callee: calleeExpr, _, _, _) = rhsExpr,
                  let calleeExprNode = ast.arena.expr(calleeExpr),
                  case let .nameRef(name, _) = calleeExprNode
            else { return false }
            return ctx.interner.resolve(name) != "listOf"
        })
        let callee = try #require(sema.bindings.callBinding(for: elementPlus)?.chosenCallee)
        let file = try #require(sema.symbols.sourceFileID(for: callee))
        #expect(ctx.sourceManager.origin(of: file) == .user)
    }

    private func requireNoErrors(_ ctx: CompilationContext) throws {
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
        try #require(errors.isEmpty, "\(errors)")
    }

    private func compoundAssignmentCallee(in ctx: CompilationContext) throws -> (SemaModule, SymbolID) {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignment = try #require(firstExprID(in: ast) { _, expr in
            guard case let .compoundAssign(_, name, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return false }
            return ctx.interner.resolve(name) == "scope"
        })
        let callee = try #require(sema.bindings.callBinding(for: assignment)?.chosenCallee)
        return (sema, callee)
    }

    private func userBinaryPlusExprIDs(in ctx: CompilationContext) -> [ExprID] {
        guard let ast = ctx.ast else { return [] }
        return ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .binary(op, _, _, range) = expr,
                  op == .add,
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { return nil }
            return exprID
        }
    }
}
