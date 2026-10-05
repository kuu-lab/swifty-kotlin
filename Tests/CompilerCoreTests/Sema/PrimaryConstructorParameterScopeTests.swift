@testable import CompilerCore
import Testing

@Suite
struct PrimaryConstructorParameterScopeTests {
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
