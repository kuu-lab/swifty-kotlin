@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-019/063: Consolidated Sema coverage for `String.indent(n: Int)`
/// and `String.reversed()`. A single Sema pass resolves all source packages and
/// each `do` block verifies the expected per-path diagnostics.
@Suite
struct StringTransformFunctionTests {
    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testIndentAndReversedResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun main() {
                val noArg: String = "hello".indent()
                val withInt: String = "hello".indent(2)
                val negative: String = "  hello".indent(-2)
                val returnIsString: Int = "  hello".indent(2).length
                val chained: String = "  abc".indent(2).trim()
            }
            """,
            """
            package sample1
            fun main() {
                val s = "hello".indent("  ")
            }
            """,
            """
            package sample2
            fun main() {
                val literal: String = "hello".reversed()
                val source: String = "kotlin"
                val flipped: String = source.reversed()
                val n: Int = "abcde".reversed().length
                val chained: String = "abc".reversed().reversed()
            }
            """,
            """
            package sample3
            fun main() {
                val s = "abc".reversed(1)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // === indent resolves cleanly ===
            do {
                let path = paths[0]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains { $0.severity == .error },
                    "resolve: \(pathDiagnostics)"
                )
            }

            // === indent rejects String argument ===
            do {
                let path = paths[1]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    pathDiagnostics.contains { $0.severity == .error },
                    "expected error for String argument to indent, got: \(pathDiagnostics)"
                )
            }

            // === reversed resolves cleanly ===
            do {
                let path = paths[2]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains { $0.severity == .error },
                    "resolve: \(pathDiagnostics)"
                )
            }

            // === reversed accepts no arguments ===
            do {
                let path = paths[3]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    pathDiagnostics.contains { $0.severity == .error },
                    "expected error for extra argument, got: \(pathDiagnostics)"
                )
            }
        }
    }
}
