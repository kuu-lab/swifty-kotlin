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
}
