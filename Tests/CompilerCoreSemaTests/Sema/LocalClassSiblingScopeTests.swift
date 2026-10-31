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

    // KUU-3880: a local class's explicit `private constructor` is scoped to
    // the class body, so `C()` in the enclosing function is rejected — same
    // as kotlinc. Implicit or unannotated constructors keep working because
    // they inherit the local class's own private visibility through
    // `.constructorVisibilityInherited`, which delegates the check back to
    // the class.
    @Test(arguments: [
        ("""
        fun main() {
            class C private constructor() {
                fun foo() = 1
            }
            val c = C()
            println(c.foo())
        }
        """, 5),
        ("""
        class Outer {
            fun f() {
                class C private constructor() {
                    fun foo() = 1
                }
                val c = C()
            }
        }
        """, 6),
    ])
    func rejectsPrivateConstructorOfLocalClassFromEnclosingScope(
        source: String, expectedLine: Int
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.severity == .error && diagnostic.code == "KSWIFTK-SEMA-0040"
                    && diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } == expectedLine
            }, "Expected a private-constructor error at line \(expectedLine): \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        // Members inside the local class body can still call the private
        // primary constructor, and private members resolve in-class.
        """
        fun main() {
            class C private constructor() {
                fun make() = C()
                private val x = 1
                fun read() = x
            }
        }
        """,
        // The public secondary constructor stays callable from the enclosing
        // scope even when a private secondary exists.
        """
        fun main() {
            class C {
                private constructor(x: Int)
                constructor() : this(1)
            }
            val ok = C()
        }
        """,
        // Unannotated and `internal` constructors on a local class keep
        // inheriting the class's private visibility, so they stay callable
        // in the enclosing function.
        """
        fun main() {
            class C(val v: Int)
            class D internal constructor(val w: Int)
            val c = C(1)
            val d = D(2)
            println(c.v + d.w)
        }
        """,
        // Members of an object literal are still reachable on the instance
        // when they are not private.
        """
        fun main() {
            val o = object {
                private val hidden = 1
                fun read() = hidden
            }
            println(o.read())
        }
        """,
    ])
    func acceptsLocalNominalUsesInsideTheirVisibilityScope(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    // A `private` member property of a local class or object literal is
    // scoped to that body; reads from the enclosing scope are rejected.
    @Test(arguments: [
        ("""
        fun main() {
            class C {
                private val x = 1
            }
            val c = C()
            println(c.x)
        }
        """, 6),
        ("""
        class Outer {
            fun probe() {
                class C {
                    private val x = 1
                }
                println(C().x)
            }
        }
        """, 6),
        ("""
        fun main() {
            val o = object {
                private val x = 1
            }
            println(o.x)
        }
        """, 5),
    ])
    func rejectsPrivateMemberPropertyOfLocalNominalFromEnclosingScope(
        source: String, expectedLine: Int
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = context(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.severity == .error && diagnostic.code == "KSWIFTK-SEMA-0040"
                    && diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } == expectedLine
            }, "Expected a private-member error at line \(expectedLine): \(ctx.diagnostics.diagnostics)")
        }
    }
}
