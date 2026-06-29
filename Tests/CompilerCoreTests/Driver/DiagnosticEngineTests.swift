#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DiagnosticEngineTests {
    // MARK: - Emit and Severity Helpers

    @Test
    func testEmitAppendsDiagnostic() {
        let engine = DiagnosticEngine()
        let diag = Diagnostic(
            severity: .error,
            code: "E001",
            message: "test error",
            primaryRange: nil,
            secondaryRanges: []
        )
        engine.emit(diag)
        #expect(engine.diagnostics.count == 1)
        #expect(engine.diagnostics[0].code == "E001")
    }

    @Test
    func testErrorHelperEmitsErrorSeverity() {
        let engine = DiagnosticEngine()
        engine.error("E-ERR", "an error", range: nil)
        #expect(engine.diagnostics.count == 1)
        #expect(engine.diagnostics[0].severity == .error)
        #expect(engine.diagnostics[0].code == "E-ERR")
        #expect(engine.diagnostics[0].message == "an error")
        #expect(engine.diagnostics[0].primaryRange == nil)
    }

    @Test
    func testWarningHelperEmitsWarningSeverity() {
        let engine = DiagnosticEngine()
        engine.warning("W-WARN", "a warning", range: nil)
        #expect(engine.diagnostics.count == 1)
        #expect(engine.diagnostics[0].severity == .warning)
    }

    @Test
    func testNoteHelperEmitsNoteSeverity() {
        let engine = DiagnosticEngine()
        engine.note("N-NOTE", "a note", range: nil)
        #expect(engine.diagnostics.count == 1)
        #expect(engine.diagnostics[0].severity == .note)
    }

    @Test
    func testInfoHelperEmitsInfoSeverity() {
        let engine = DiagnosticEngine()
        engine.info("I-INFO", "info msg", range: nil)
        #expect(engine.diagnostics.count == 1)
        #expect(engine.diagnostics[0].severity == .info)
    }

    @Test
    func testEmitWithRange() {
        let engine = DiagnosticEngine()
        let range = makeRange(start: 5, end: 10)
        engine.error("E-RANGE", "has range", range: range)
        #expect(engine.diagnostics[0].primaryRange == range)
    }

    // MARK: - hasError

    @Test
    func testHasErrorReturnsFalseWhenEmpty() {
        let engine = DiagnosticEngine()
        #expect(!(engine.hasError))
    }

    @Test
    func testHasErrorReturnsTrueAfterError() {
        let engine = DiagnosticEngine()
        engine.error("E", "err", range: nil)
        #expect(engine.hasError)
    }

    @Test
    func testHasErrorReturnsFalseForWarningOnly() {
        let engine = DiagnosticEngine()
        engine.warning("W", "warn", range: nil)
        #expect(!(engine.hasError))
    }

    @Test
    func testHasErrorReturnsFalseForNoteOnly() {
        let engine = DiagnosticEngine()
        engine.note("N", "note", range: nil)
        #expect(!(engine.hasError))
    }

    @Test
    func testHasErrorReturnsFalseForInfoOnly() {
        let engine = DiagnosticEngine()
        engine.info("I", "info", range: nil)
        #expect(!(engine.hasError))
    }

    // MARK: - Render

    @Test
    func testRenderReturnsEmptyStringWhenNoDiagnostics() {
        let engine = DiagnosticEngine()
        let srcMgr = SourceManager()
        #expect(engine.render(srcMgr) == "")
    }

    @Test
    func testRenderFormatsWithoutRange() {
        let engine = DiagnosticEngine()
        engine.error("E-001", "something bad", range: nil)
        let srcMgr = SourceManager()
        let rendered = engine.render(srcMgr)
        #expect(rendered.contains("error E-001: something bad"))
    }

    @Test
    func testRenderFormatsWithRange() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "test.kt", contents: Data("line1\nline2\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 6),
            end: SourceLocation(file: fileID, offset: 11)
        )
        let engine = DiagnosticEngine()
        engine.error("E-002", "bad line2", range: range)
        let rendered = engine.render(srcMgr)
        #expect(rendered.contains("test.kt:2:1:"))
        #expect(rendered.contains("error E-002: bad line2"))
    }

    @Test
    func testRenderSortsByFileThenLineColumn() {
        let srcMgr = SourceManager()
        let fileA = srcMgr.addFile(path: "a.kt", contents: Data("abc\ndef\n".utf8))
        let fileB = srcMgr.addFile(path: "b.kt", contents: Data("xyz\n".utf8))

        let engine = DiagnosticEngine()
        engine.error("E-B", "in b", range: SourceRange(
            start: SourceLocation(file: fileB, offset: 0),
            end: SourceLocation(file: fileB, offset: 3)
        ))
        engine.error("E-A1", "in a line 2", range: SourceRange(
            start: SourceLocation(file: fileA, offset: 4),
            end: SourceLocation(file: fileA, offset: 7)
        ))
        engine.error("E-A0", "in a line 1", range: SourceRange(
            start: SourceLocation(file: fileA, offset: 0),
            end: SourceLocation(file: fileA, offset: 3)
        ))

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("E-A0"))
        #expect(lines[1].contains("E-A1"))
        #expect(lines[2].contains("E-B"))
    }

    @Test
    func testRenderSortsSeveritiesWithinSameLocation() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "same.kt", contents: Data("x\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        )

        let engine = DiagnosticEngine()
        engine.warning("W-1", "warn", range: range)
        engine.error("E-1", "err", range: range)

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 2)
        // Errors (rank 0) come before warnings (rank 1)
        #expect(lines[0].contains("error"))
        #expect(lines[1].contains("warning"))
    }

    @Test
    func testRenderRangelessDiagnosticsComeLast() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "f.kt", contents: Data("a\n".utf8))

        let engine = DiagnosticEngine()
        engine.error("E-NORANGE", "no range", range: nil)
        engine.error("E-RANGE", "has range", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 1)
        ))

        let rendered = engine.render(srcMgr)
        let lines = rendered.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("E-RANGE"))
        #expect(lines[1].contains("E-NORANGE"))
    }

    @Test
    func testRenderSeverityLabels() {
        let srcMgr = SourceManager()
        let engine = DiagnosticEngine()
        engine.error("E", "e", range: nil)
        engine.warning("W", "w", range: nil)
        engine.note("N", "n", range: nil)
        engine.info("I", "i", range: nil)

        let rendered = engine.render(srcMgr)
        #expect(rendered.contains("error E:"))
        #expect(rendered.contains("warning W:"))
        #expect(rendered.contains("note N:"))
        #expect(rendered.contains("info I:"))
    }

    // MARK: - Multiple Diagnostics

    @Test
    func testMultipleDiagnosticsAccumulateInOrder() {
        let engine = DiagnosticEngine()
        engine.error("E1", "first", range: nil)
        engine.warning("W1", "second", range: nil)
        engine.note("N1", "third", range: nil)
        #expect(engine.diagnostics.count == 3)
        #expect(engine.diagnostics[0].code == "E1")
        #expect(engine.diagnostics[1].code == "W1")
        #expect(engine.diagnostics[2].code == "N1")
    }

    // MARK: - Diagnostic Equality

    @Test
    func testDiagnosticEquality() {
        let d1 = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        let d2 = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        let d3 = Diagnostic(severity: .warning, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        #expect(d1 == d2)
        #expect(d1 != d3)
    }

    @Test
    func testDiagnosticWithSecondaryRanges() {
        let range1 = makeRange(start: 0, end: 5)
        let range2 = makeRange(start: 10, end: 15)
        let diag = Diagnostic(
            severity: .error,
            code: "E",
            message: "m",
            primaryRange: range1,
            secondaryRanges: [range2]
        )
        #expect(diag.secondaryRanges.count == 1)
        #expect(diag.secondaryRanges[0] == range2)
    }

    // MARK: - JSON Rendering

    @Test
    func testRenderJSONEmptyDiagnostics() {
        let engine = DiagnosticEngine()
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"version\": 1"))
        #expect(json.contains("\"diagnostics\": ["))
    }

    @Test
    func testRenderJSONSingleErrorWithRange() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "test.kt", contents: Data("line1\nline2\n".utf8))
        let range = SourceRange(
            start: SourceLocation(file: fileID, offset: 6),
            end: SourceLocation(file: fileID, offset: 11)
        )
        let engine = DiagnosticEngine()
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: range)
        let json = engine.renderJSON(srcMgr)

        #expect(json.contains("\"version\": 1"))
        #expect(json.contains("\"file\": \"test.kt\""))
        #expect(json.contains("\"severity\": 1"))
        #expect(json.contains("\"severityLabel\": \"error\""))
        #expect(json.contains("\"code\": \"KSWIFTK-SEMA-0014\""))
        #expect(json.contains("\"source\": \"kswiftk\""))
        #expect(json.contains("\"message\": \"Type mismatch\""))
        // LSP uses 0-based lines: line1 is 0, line2 is 1
        #expect(json.contains("\"line\": 1"))
    }

    @Test
    func testRenderJSONWarningHasSeverityTwo() {
        let engine = DiagnosticEngine()
        engine.warning("KSWIFTK-SEMA-0001", "unused var", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"severity\": 2"))
        #expect(json.contains("\"severityLabel\": \"warning\""))
    }

    @Test
    func testRenderJSONNoteHasSeverityThree() {
        let engine = DiagnosticEngine()
        engine.note("KSWIFTK-SEMA-0002", "see also", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"severity\": 3"))
        #expect(json.contains("\"severityLabel\": \"note\""))
    }

    @Test
    func testRenderJSONInfoHasSeverityFour() {
        let engine = DiagnosticEngine()
        engine.info("KSWIFTK-SEMA-0003", "hint", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"severity\": 4"))
        #expect(json.contains("\"severityLabel\": \"info\""))
    }

    @Test
    func testRenderJSONCodeActionsFromRegistry() {
        let engine = DiagnosticEngine()
        // KSWIFTK-SEMA-0014 has a registry codeAction: "Add explicit type cast"
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"codeActions\""))
        #expect(json.contains("\"title\": \"Add explicit type cast\""))
        #expect(json.contains("\"kind\": \"quickfix\""))
    }

    @Test
    func testRenderJSONExplicitCodeActionOverridesRegistry() {
        let engine = DiagnosticEngine()
        let action = DiagnosticCodeAction(title: "Custom fix", kind: "quickfix")
        engine.error("KSWIFTK-SEMA-0014", "Type mismatch", range: nil, codeActions: [action])
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\"title\": \"Custom fix\""))
        // Should NOT contain the registry default when explicit actions are provided.
        #expect(!(json.contains("\"title\": \"Add explicit type cast\"")))
    }

    @Test
    func testRenderJSONMultipleDiagnosticsSorted() {
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "multi.kt", contents: Data("aaa\nbbb\nccc\n".utf8))
        let engine = DiagnosticEngine()
        // Emit in reverse order to verify sorting.
        engine.error("E-2", "second", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 4),
            end: SourceLocation(file: fileID, offset: 7)
        ))
        engine.error("E-1", "first", range: SourceRange(
            start: SourceLocation(file: fileID, offset: 0),
            end: SourceLocation(file: fileID, offset: 3)
        ))
        let json = engine.renderJSON(srcMgr)
        // E-1 should appear before E-2 in the output.
        guard let idx1 = json.range(of: "E-1")?.lowerBound,
              let idx2 = json.range(of: "E-2")?.lowerBound
        else {
            Issue.record("Both diagnostics should appear in JSON"); return
        }
        #expect(idx1 < idx2)
    }

    @Test
    func testRenderJSONEscapesSpecialCharacters() {
        let engine = DiagnosticEngine()
        engine.error("E-ESC", "msg with \"quotes\" and \\backslash", range: nil)
        let srcMgr = SourceManager()
        let json = engine.renderJSON(srcMgr)
        #expect(json.contains("\\\"quotes\\\""))
        #expect(json.contains("\\\\backslash"))
    }

    @Test
    func testRenderJSONSchemaVersionStability() {
        // Golden schema test: verify the top-level structure is stable.
        let srcMgr = SourceManager()
        let fileID = srcMgr.addFile(path: "schema.kt", contents: Data("val x = 1\n".utf8))
        let engine = DiagnosticEngine()
        engine.error(
            "KSWIFTK-SEMA-0022",
            "Unresolved reference: foo",
            range: SourceRange(
                start: SourceLocation(file: fileID, offset: 0),
                end: SourceLocation(file: fileID, offset: 3)
            )
        )

        let json = engine.renderJSON(srcMgr)

        // Verify all required LSP schema fields are present.
        let requiredFields = [
            "\"version\"", "\"diagnostics\"", "\"file\"",
            "\"range\"", "\"start\"", "\"end\"",
            "\"line\"", "\"character\"",
            "\"severity\"", "\"severityLabel\"",
            "\"code\"", "\"source\"", "\"message\"",
            "\"codeActions\"",
        ]
        for field in requiredFields {
            #expect(json.contains(field), "JSON should contain field: \(field)")
        }
    }

    // MARK: - DiagnosticRegistry

    @Test
    func testDiagnosticRegistryLookupKnownCode() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-SEMA-0014")
        #expect(descriptor != nil)
        #expect(descriptor?.code == "KSWIFTK-SEMA-0014")
        #expect(descriptor?.pass == "SEMA")
    }

    @Test
    func testDiagnosticRegistryLookupUnknownCode() {
        let descriptor = DiagnosticRegistry.lookup("KSWIFTK-DOES-NOT-EXIST")
        #expect(descriptor == nil)
    }

    @Test
    func testDiagnosticRegistryAllDescriptorsHaveKSWIFTKPrefix() {
        for descriptor in DiagnosticRegistry.allDescriptors {
            #expect(
                descriptor.code.hasPrefix("KSWIFTK-"),
                "Descriptor code \(descriptor.code) should start with KSWIFTK-"
            )
        }
    }

    @Test
    func testDiagnosticRegistryHasMinimumTenCodeActions() {
        let withActions = DiagnosticRegistry.allDescriptors.filter { !$0.codeActions.isEmpty }
        #expect(
            withActions.count >= 10,
            "Registry should have at least 10 diagnostics with codeActions"
        )
    }

    // MARK: - DiagnosticsFormat

    @Test
    func testDiagnosticsFormatRawValues() {
        #expect(DiagnosticsFormat(rawValue: "text") == .text)
        #expect(DiagnosticsFormat(rawValue: "json") == .json)
        #expect(DiagnosticsFormat(rawValue: "xml") == nil)
    }

    // MARK: - codeActions on Diagnostic

    @Test
    func testDiagnosticCodeActionsDefaultToEmpty() {
        let diag = Diagnostic(severity: .error, code: "E", message: "m", primaryRange: nil, secondaryRanges: [])
        #expect(diag.codeActions.isEmpty)
    }

    @Test
    func testDiagnosticCodeActionsCanBeProvided() {
        let action = DiagnosticCodeAction(title: "Fix it", kind: "quickfix")
        let diag = Diagnostic(
            severity: .error, code: "E", message: "m",
            primaryRange: nil, secondaryRanges: [],
            codeActions: [action]
        )
        #expect(diag.codeActions.count == 1)
        #expect(diag.codeActions[0].title == "Fix it")
    }
}
#endif
