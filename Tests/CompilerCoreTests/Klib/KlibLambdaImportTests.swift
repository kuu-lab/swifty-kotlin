@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibLambdaImportTests {
    private var fixture: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Kotlin2_4_21/Lambdas/lambdas.klib").path
    }

    @Test
    func importsNumberedFunctionClassifiersAsFunctionTypes() throws {
        let phase = DataFlowSemaPhase()
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let loaded = try #require(phase.loadKlibModule(path: fixture, diagnostics: diagnostics))
        let records = phase.materializeKlibRecords(module: loaded, interner: interner, diagnostics: diagnostics).records
        func signature(_ name: String) throws -> String {
            try #require(records.first {
                $0.fqName.map { interner.resolve($0) } == ["kliblambdas", name]
            }?.typeSignature)
        }
        #expect(try signature("make") == "F0<F1<I,I>>")
        #expect(try signature("capture") == "F1<I,F1<I,I>>")
        #expect(try signature("nested") == "F1<I,F1<I,F0<I>>>")
        #expect(try signature("apply") == "F2<F1<I,I>,I,I>")
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test
    func discoversLexicalAndTransitiveCapturesInLatestRichReferences() throws {
        let module = try KlibIrModule(container: KlibContainer(path: fixture))
        var checked: Set<String> = []
        for fileIndex in 0 ..< module.fileCount {
            for case .function(let function) in try module.declarations(fileIndex: fileIndex) {
                let name = try module.string(function.base.nameType.nameIndex, fileIndex: fileIndex)
                guard ["make", "capture", "twoCaptures", "nested", "counter", "sharedState"].contains(name) else { continue }
                let body = try module.body(#require(function.base.bodyIndex), fileIndex: fileIndex)
                guard case .blockBody(let statements) = body.kind,
                      case .expression(let returned) = statements.last?.kind,
                      case .return(_, let value) = returned.kind,
                      case .richFunctionReference(let boundValues, _, _, let lambda, _, _) = value.kind else {
                    Issue.record("expected returned rich lambda in \(name)")
                    continue
                }
                #expect(boundValues.isEmpty)
                var available = Set(function.base.regularParameters.map { $0.base.symbol.signatureIndex })
                for statement in statements {
                    if case .declaration(.variable(let variable)) = statement.kind {
                        available.insert(variable.base.symbol.signatureIndex)
                    }
                }
                let captures = try KlibLambdaCaptureAnalysis.captures(
                    of: lambda, module: module, fileIndex: fileIndex, available: available
                )
                let expected: Int
                switch name {
                case "make": expected = 0
                case "twoCaptures", "sharedState": expected = 2
                default: expected = 1
                }
                #expect(captures.count == expected, "\(name): \(captures)")
                #expect(Set(captures).isSubset(of: available))
                checked.insert(name)
            }
        }
        #expect(checked == ["make", "capture", "twoCaptures", "nested", "counter", "sharedState"])
    }
}
