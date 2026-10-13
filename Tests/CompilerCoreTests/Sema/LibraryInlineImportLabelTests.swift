#if canImport(Testing)
@testable import CompilerCore
import CompilerTestSupport
import Foundation
import Testing

@Suite
struct LibraryInlineImportLabelTests {
    @Test
    func testParameterCallUsesTheSameLocalIdentityAsItsReference() throws {
        let types = TypeSystem()
        let callback = types.make(.functionType(FunctionType(params: [], returnType: types.booleanType)))
        let name = "kotlin.helper.predicate"
        let encodedName = Data(name.utf8).base64EncodedString()
        var imported: KIRFunction?
        try withTemporaryFile(contents: """
        params=1
        paramSymbols=10
        body:
        const result=20 value=symbol:10
        call symbol=10 calleeB64=a2tfZnVuY3Rpb25faW52b2tlXzA= args=[20] result=21 symbolFQNameB64=\(encodedName)
        returnValue value=21
        """, fileExtension: "kir") { path in
            imported = DataFlowSemaPhase.parseImportedInlineFunction(
                path: path, importedSymbol: SymbolID(rawValue: 100),
                signature: FunctionSignature(parameterTypes: [callback], returnType: types.booleanType),
                types: types, interner: StringInterner(), diagnostics: DiagnosticEngine(),
                externalLinkNameToSymbol: [:], importedSymbolByFQName: [name: SymbolID(rawValue: 900)]
            )
        }
        let function = try #require(imported)
        guard case let .constValue(_, .symbolRef(reference)) = function.body[0],
              case let .call(callee, _, _, _, _, _, _, _) = function.body[1]
        else {
            Issue.record("Expected a parameter reference followed by its invocation")
            return
        }
        #expect(reference == function.params[0].symbol)
        #expect(callee == reference)
        #expect(callee != SymbolID(rawValue: 900))
    }

    @Test
    func testImportedReifiedHigherOrderFunctionKeepsRawTokenParameter() throws {
        let types = TypeSystem()
        let callback = types.make(.functionType(FunctionType(params: [], returnType: types.stringType)))
        let signature = FunctionSignature(
            parameterTypes: [types.nullableAnyType, callback], returnType: types.anyType,
            typeParameterSymbols: [SymbolID(rawValue: 77)], reifiedTypeParameterIndices: [0]
        )
        var imported: KIRFunction?
        try withTemporaryFile(contents: """
        params=3
        paramSymbols=10,11,12
        body:
        returnUnit
        """, fileExtension: "kir") { path in
            imported = DataFlowSemaPhase.parseImportedInlineFunction(
                path: path, importedSymbol: SymbolID(rawValue: 100), signature: signature,
                types: types, interner: StringInterner(), diagnostics: DiagnosticEngine(),
                externalLinkNameToSymbol: [:], importedSymbolByFQName: [:]
            )
        }
        let function = try #require(imported)
        #expect(function.params.map(\.type) == [types.nullableAnyType, callback, types.intType])
    }

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
    func testCleanupContinuationsSurviveParsingAndMaterialization() throws {
        let artifact = """
        params=0
        body:
        beginNonLocalReturnScope value=500 target=10
        beginFinallyCleanup skipping=1
        endFinallyCleanup
        endNonLocalReturnScope
        label id=10
        resumeNonLocalReturn value=500
        returnUnit
        """
        let (parsed, diags) = try parseInlineArtifact(content: artifact)
        #expect(!diags.hasError)
        let function = try #require(parsed)
        var imported = [function.symbol: function]
        let arena = KIRArena()
        ImportedInlineKIRMaterializer.materialize(
            importedFunctions: &imported, arena: arena, types: TypeSystem(), interner: StringInterner()
        )
        let body = try #require(imported[function.symbol]?.body)
        guard case let .beginNonLocalReturnScope(slot, target, _) = body[0] else {
            Issue.record("Expected cleanup scope")
            return
        }
        #expect(slot.rawValue != 500)
        #expect(arena.expr(slot) != nil)
        #expect(target == 10)
        #expect(body[1] == .beginFinallyCleanup(skipping: 1))
        #expect(body[5] == .resumeNonLocalReturn(slot))
    }

    @Test
    func testPrivateReturnTargetKeepsLinkIdentity() throws {
        let link = "private_inline_value"
        let encoded = Data(link.utf8).base64EncodedString()
        let artifact = """
        params=0
        body:
        beginNonLocalReturnScope value=500 target=10 functionB64=\(encoded)
        nonLocalReturn value=501 targetB64=\(encoded)
        endNonLocalReturnScope
        label id=10
        returnUnit
        """
        let (parsed, diags) = try parseInlineArtifact(content: artifact)
        #expect(!diags.hasError)
        let function = try #require(parsed)
        guard case let .beginNonLocalReturnScope(_, _, target) = function.body[0],
              case let .nonLocalReturn(_, returnTarget) = function.body[1] else {
            Issue.record("Expected named return scope and return")
            return
        }
        #expect(target != nil)
        #expect(target == returnTarget)
        guard case .importedFunction = target else {
            Issue.record("Expected private inline target link")
            return
        }
    }

    @Test
    func testMalformedReturnTargetRejectsInlineBody() throws {
        let (function, diags) = try parseInlineArtifact(content: """
        params=0
        body:
        nonLocalReturnUnit targetB64=%%%
        """)
        #expect(function == nil)
        #expect(diags.diagnostics.contains { $0.code == "KSWIFTK-LIB-0023" })
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
