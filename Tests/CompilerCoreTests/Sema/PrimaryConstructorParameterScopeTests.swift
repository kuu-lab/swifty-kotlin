@testable import CompilerCore
import Testing

@Suite
struct PrimaryConstructorParameterScopeTests {
    @Test
    func onlyEnumClassesCollectEnumEntries() throws {
        let source = """
        class B(d: Int) {
            init { if (d < 2) println("small") }
        }
        enum class E(d: Int) {
            ONE(1), TWO(2);
            init { if (d < 2) println("small") }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontend(ctx)
            let ast = try #require(ctx.ast)
            let classes = ast.arena.decls.compactMap { decl -> ClassDecl? in
                guard case let .classDecl(classDecl) = decl else { return nil }
                return classDecl
            }
            let ordinary = try #require(classes.first { $0.name == ctx.interner.intern("B") })
            #expect(ordinary.enumEntries.isEmpty)
            #expect(ordinary.initBlocks.count == 1)
            let enumeration = try #require(classes.first { $0.name == ctx.interner.intern("E") })
            #expect(enumeration.enumEntries.map { ctx.interner.resolve($0.name) } == ["ONE", "TWO"])
            #expect(enumeration.initBlocks.count == 1)
        }
    }

    @Test(arguments: ["", ": Base(d.inner)"])
    func nonPropertyObjectParameterIsVisibleInInitBlock(supertype: String) throws {
        let source = """
        fun println(value: String) {}
        class Wrap(val inner: Int)
        open class Base(val value: Int)
        class B(d: Wrap) \(supertype) {
            init {
                if (d.inner < 2) println("small")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    @Test(arguments: [
        "fun get() = x",
        "fun get(): Int = x",
        "fun get(): Int { return x }",
        "val value: Int get() = x",
    ])
    func nonPropertyParameterIsNotVisibleInMemberBodies(member: String) throws {
        let source = """
        class Box(x: Int) {
            \(member)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            let error = try #require(errors.first)
            #expect(error.code == "KSWIFTK-SEMA-0022")
            #expect(error.message == "Unresolved reference 'x'.")
        }
    }

    @Test
    func nonPropertyParameterIsVisibleDuringInitialization() throws {
        let source = """
        class Box(x: Int) {
            val copied: Int = x
            var initialized: Int = 0
            init { initialized = x }
            fun get(): Int = copied + initialized
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    @Test(arguments: ["val", "var"])
    func propertyParameterIsVisibleInMemberBodies(keyword: String) throws {
        let source = """
        class Box(\(keyword) x: Int) {
            fun get(): Int = x
            fun getFromBlock(): Int { return x }
            val value: Int get() = x
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
