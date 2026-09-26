#if canImport(Testing)
@testable import CompilerCore
import CompilerTestSupport
import Foundation
import Testing

@Suite
struct LibraryInlineImportLabelTests {
    private func parseInlineArtifact(
        content: String,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) throws -> (function: KIRFunction?, diagnostics: DiagnosticEngine) {
        let types = TypeSystem()
        let interner = StringInterner()
        var resultFunction: KIRFunction?

        try withTemporaryFile(contents: content, fileExtension: "kir") { path in
            resultFunction = DataFlowSemaPhase.parseImportedInlineFunction(
                path: path,
                importedSymbol: SymbolID(rawValue: 100),
                signature: nil,
                types: types,
                interner: interner,
                diagnostics: diagnostics,
                externalLinkNameToSymbol: [:],
                importedSymbolByFQName: [:]
            )
        }
        return (resultFunction, diagnostics)
    }

    @Test
    func testDefinedLabelAtInt32MaxIsRejectedWithDiagnostic() throws {
        let artifact = """
        params=0
        body:
        label id=\(Int32.max)
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
    }

    @Test
    func testJumpTargetAtInt32MaxIsRejectedWithDiagnostic() throws {
        let artifact = """
        params=0
        body:
        jump target=\(Int32.max)
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
    }

    @Test
    func testJumpIfEqualTargetAtInt32MaxIsRejectedWithDiagnostic() throws {
        let artifact = """
        params=0
        body:
        jumpIfEqual lhs=1 rhs=2 target=\(Int32.max)
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
    }

    @Test
    func testJumpIfNotNullTargetAtInt32MaxIsRejectedWithDiagnostic() throws {
        let artifact = """
        params=0
        body:
        jumpIfNotNull value=1 target=\(Int32.max)
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
    }

    @Test
    func testNegativeLabelIsRejectedWithDiagnostic() throws {
        let artifact = """
        params=0
        body:
        label id=-1
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
    }

    @Test
    func testMaxSupportedLabelIsAccepted() throws {
        let maxLabel = InlineLabelAllocator.maxSupportedLabel
        let artifact = """
        params=0
        body:
        label id=\(maxLabel)
        jump target=\(maxLabel)
        returnUnit
        """
        let (function, diags) = try parseInlineArtifact(content: artifact)
        #expect(function != nil)
        #expect(!diags.hasError)
        #expect(diags.diagnostics.filter { $0.code == "KSWIFTK-LIB-0023" }.isEmpty)
        #expect(function?.body.contains(where: {
            if case let .label(id) = $0 { return id == maxLabel }
            return false
        }) == true)
        #expect(function?.body.contains(where: {
            if case let .jump(target) = $0 { return target == maxLabel }
            return false
        }) == true)
    }
}
#endif
