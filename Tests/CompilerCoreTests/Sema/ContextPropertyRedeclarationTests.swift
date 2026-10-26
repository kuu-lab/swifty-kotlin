#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ContextPropertyRedeclarationTests {
    @Test
    func contextAndOrdinaryPropertiesInOneFileCoexist() throws {
        let source = """
        class A
        context(a: A) val b: Int get() = 1
        val b: Int get() = 2
        fun read(): Int = b
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Context and ordinary properties should coexist: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func contextAndOrdinaryPropertiesCoexistRegardlessOfDeclarationOrder(reverse: Bool) throws {
        let contextSource = """
        package sample
        class A
        context(a: A)
        val b: Int get() = 1
        """
        let ordinarySource = """
        package sample
        val b: Int get() = 2
        fun read(): Int = b
        """
        let sources = reverse ? [ordinarySource, contextSource] : [contextSource, ordinarySource]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Context and ordinary properties should coexist: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func contextPropertiesWithDifferentParameterTypesCoexist() throws {
        let source = """
        class A
        class B
        context(a: A) val value: Int get() = 1
        context(b: B) val value: Int get() = 2
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Different context parameter types should distinguish properties: \(errors)")
        }
    }

    @Test
    func contextPropertiesWithIdenticalParameterTypesConflict() throws {
        let source = """
        class A
        context(a: A) val value: Int get() = 1
        context(other: A) val value: Int get() = 2
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let duplicates = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0001" }
            #expect(duplicates.count == 1, "Identical context parameter types should conflict: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
