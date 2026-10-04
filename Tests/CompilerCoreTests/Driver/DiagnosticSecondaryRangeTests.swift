#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// ARCH-031: `Diagnostic.secondaryRanges` are populated for type mismatches
// (expected type's origin) and ambiguous overloads (candidate declaration
// sites), and are rendered by both the text and JSON diagnostic renderers.
@Suite
struct DiagnosticSecondaryRangeTests {
    private func compileDiagnostics(
        _ source: String,
        body: (CompilationContext) throws -> Void
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "SecondaryRange",
                emit: .kirDump
            )
            try? runFrontend(ctx)
            try? runSema(ctx)
            try body(ctx)
        }
    }

    @Test
    func testTypeMismatchAttachesExpectedTypeDeclSite() throws {
        let source = """
        class Foo
        fun main() {
            val x: Foo = "hello"
        }
        """
        try compileDiagnostics(source) { ctx in
            let mismatches = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-TYPE-0001" }
            let mismatch = try #require(mismatches.first)
            let file = try #require(mismatch.primaryRange?.start.file)
            let secondary = try #require(mismatch.secondaryRanges.first)
            #expect(secondary.start.file == file)
            // The secondary range points at `class Foo`'s declaration site.
            #expect(ctx.sourceManager.slice(secondary).hasPrefix("class Foo"))
        }
    }

    @Test
    func testAmbiguousOverloadAttachesCandidateDeclSites() throws {
        let source = """
        fun pick(x: Int?, y: Int): Int = 0
        fun pick(x: Int, y: Int?): Int = 1
        fun main() {
            println(pick(1, 1))
        }
        """
        try compileDiagnostics(source) { ctx in
            let ambiguous = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0003" }
            let diagnostic = try #require(ambiguous.first)
            // Both `pick` overloads are reported, in source order.
            #expect(diagnostic.secondaryRanges.count == 2)
            let first = try #require(diagnostic.secondaryRanges.first)
            let last = try #require(diagnostic.secondaryRanges.last)
            #expect(ctx.sourceManager.slice(first).hasPrefix("fun pick(x: Int?"))
            #expect(ctx.sourceManager.slice(last).hasPrefix("fun pick(x: Int,"))
            #expect(first.start.offset < last.start.offset)
        }
    }

    @Test
    func testTextRendererEmitsNoteLinesForSecondaryRanges() throws {
        let source = """
        fun pick(x: Int?, y: Int): Int = 0
        fun pick(x: Int, y: Int?): Int = 1
        fun main() {
            println(pick(1, 1))
        }
        """
        try compileDiagnostics(source) { ctx in
            let rendered = ctx.diagnostics.render(ctx.sourceManager)
            #expect(rendered.contains("note: candidate declared here"))
        }
    }

    @Test
    func testJSONRendererEmitsRelatedInformation() throws {
        let source = """
        class Foo
        fun main() {
            val x: Foo = "hello"
        }
        """
        try compileDiagnostics(source) { ctx in
            let json = ctx.diagnostics.renderJSON(ctx.sourceManager)
            #expect(json.contains("\"relatedInformation\""))
            #expect(json.contains("expected type declared here"))
        }
    }
}
#endif
