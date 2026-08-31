#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// BUG-218: private top-level callables are file-scoped, while JVM-erased
/// conflicts for same-file and non-private declarations remain diagnostics.
@Suite
struct Bug218PrivateTopLevelConflictTests {
    @Test
    func testPrivateTopLevelFunctionsInDifferentFilesDoNotConflictOrMerge() throws {
        let sources = [
            """
            package demo

            private fun helper(): Int = 1
            fun callFromA(): Int = helper()
            """,
            """
            package demo

            private fun helper(): Int = 2
            fun callFromB(): Int = helper()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics")

            let sema = try #require(ctx.sema)
            let helperFQName = [
                ctx.interner.intern("demo"),
                ctx.interner.intern("helper"),
            ]
            let helperSymbols = sema.symbols.lookupAll(fqName: helperFQName)
                .filter { sema.symbols.symbol($0)?.kind == .function }
            #expect(helperSymbols.count == 2, "Expected one helper symbol per source file")

            let helperFileIDs = Set(helperSymbols.compactMap { sema.symbols.sourceFileID(for: $0) })
            #expect(helperFileIDs.count == 2, "Expected distinct source-file identities")

            let boundHelperSymbols = Set(
                sema.bindings.callBindings.values
                    .map(\.chosenCallee)
                    .filter { helperSymbols.contains($0) }
            )
            #expect(
                boundHelperSymbols == Set(helperSymbols),
                "Each file-local call should bind to its own helper symbol"
            )
        }
    }

    @Test
    func testPrivateTopLevelFunctionsInSameFileStillConflict() throws {
        let source = """
        package demo

        private fun helper(): Int = 1
        private fun helper(): Int = 2
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
        }
    }

    @Test
    func testPublicTopLevelFunctionsAcrossFilesStillConflict() throws {
        let sources = [
            """
            package demo
            fun helper(): Int = 1
            """,
            """
            package demo
            fun helper(): Int = 2
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
        }
    }

    @Test
    func testInternalTopLevelFunctionsAcrossFilesStillConflict() throws {
        let sources = [
            """
            package demo
            internal fun helper(): Int = 1
            """,
            """
            package demo
            internal fun helper(): Int = 2
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
        }
    }
}
#endif
