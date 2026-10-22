import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite
struct LocalClassSiblingScopeTests {
    private func context(inputs: [String], useCache: Bool = false) -> CompilationContext {
        TestStdlibCache.shared.prepare()
        return makeCompilationContext(
            inputs: inputs, frontendFlags: useCache ? ["sema-cache"] : [],
            stdlibLibraryPath: CompilerOptions.defaultStdlibLibraryPath
        )
    }

    @Test
    func rejectsSelfInheritanceWithAnOuterSameNamedClass() throws {
        let source = """
        open class S
        fun main() {
            class S : S()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-SUPER-CYCLE"
                    && diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } == 3
            }, "Expected the local class to inherit from itself: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func resolvesEachLocalClassInItsOwnHeaders() throws {
        let source = """
        interface Parent<T>
        fun main() {
            run {
                class S(val next: S?) : Parent<S> {
                    val self: S = this
                    fun identity(value: S): S = value
                }
                val s: S = S(null)
                println(s.identity(s).self === s)
            }
            run {
                class S(val next: S?) : Parent<S> {
                    val other: S = this
                    fun identity(value: S): S = value
                }
                val s: S = S(null)
                println(s.identity(s).other === s)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        """
        fun main() {
            class Node(val v: Int, var left: Node? = null) {
                fun preOrder() { left?.preOrder() }
            }
            Node(1).preOrder()
        }
        """,
        """
        fun main() {
            data class Node(val v: Int, var left: Node? = null)
            Node(1)
        }
        """,
    ])
    func resolvesSelfTypesInLocalClassHeaders(_ source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func resolvesMembersOfEachLexicalClass(useCache: Bool) throws {
        let source = try diffCaseSource("local_class_sibling_scopes.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path], useCache: useCache)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func resolvesOrdinaryBlocksAndDoWhileConditions() throws {
        let source = try repositoryFileSource(
            "Tests/CompilerBackendTests/Fixtures/basic/local_class_block_scopes/local_class_block_scopes.kt",
            file: #filePath
        )
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func doWhileConditionSeesBodyLocalAndInitializesOuterLocal() throws {
        let source = """
        fun main(): Int {
            var result: Int
            do {
                val stop = true
                result = 1
            } while (!stop)
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        ("""
        fun main() {
            run { class S { fun first() = 1 }; println(S().first()) }
            run { class S { fun second() = 2 }; println(S().first()) }
        }
        """, "KSWIFTK-SEMA-0024", "Unresolved member function 'first'.", 3),
        ("""
        fun main() {
            run { class S { val a = 1 }; println(S().a) }
            run { class S { val b = 2 }; println(S().a) }
        }
        """, "KSWIFTK-SEMA-0024", "Unresolved member function 'a'.", 3),
        ("""
        fun main() {
            run { class S { val a = 1 }; println(S().a) }
            println(S().a)
        }
        """, "KSWIFTK-SEMA-0023", "Unresolved function 'S'.", 3),
        ("""
        fun main() {
            run { class S { val a = 1 }; println(S().a) }
            val s: S
        }
        """, "KSWIFTK-SEMA-0025", "Unresolved type 'S'.", 3),
        ("""
        fun main() {
            do { class S { fun again() = false } } while (S().again())
            S()
        }
        """, "KSWIFTK-SEMA-0023", "Unresolved function 'S'.", 3),
        ("""
        fun main() {
            do {
                if (true) { class S { fun again() = false }; S() }
            } while (S().again())
        }
        """, "KSWIFTK-SEMA-0023", "Unresolved function 'S'.", 4),
    ])
    func rejectsClassesAndMembersOutsideTheirScope(
        source: String, expectedCode: String, expectedMessage: String, expectedLine: Int
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.severity == .error && diagnostic.code == expectedCode
                    && diagnostic.message == expectedMessage
                    && diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } == expectedLine
            }, "Expected a scope error at line \(expectedLine): \(ctx.diagnostics.diagnostics)")
        }
    }
}
