#if canImport(Testing)
@testable import CompilerCore
@testable import LSPServer
import Testing

@Suite("LSP.Analyzer")
struct AnalyzerTests {
    private let uri = "file:///tmp/LSPAnalyzer.kt"

    @Test
    func analyzeValidProgramProducesAST() {
        let source = """
        fun greet(name: String): String {
            return "Hello, " + name
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)

        #expect(analysis.context.ast != nil, "Frontend should build an AST for valid input")
        #expect(analysis.fileID != nil, "The analyzed document should be registered in the source manager")

        let errors = analysis.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Valid program should not produce error diagnostics: \(errors)")
    }

    @Test
    func analyzeReportsDiagnosticsForBrokenProgram() {
        // Unterminated declaration / garbage tokens guarantee parse diagnostics.
        let source = """
        fun broken( {
            val =
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let diagnostics = DiagnosticsFeature.lspDiagnostics(for: analysis)

        #expect(!diagnostics.isEmpty, "Malformed program should produce diagnostics")
        for diagnostic in diagnostics {
            #expect(diagnostic.source == "kswiftk")
            #expect(diagnostic.severity != nil, "Each diagnostic should carry an LSP severity")
            #expect(diagnostic.code != nil, "Each diagnostic should carry a KSWIFTK code")
        }
    }

    @Test
    func removeDropsCachedAnalysis() {
        let analyzer = Analyzer()
        _ = analyzer.analyze(uri: uri, text: "fun main() {}")
        #expect(analyzer.analysis(for: uri) != nil)
        analyzer.remove(uri: uri)
        #expect(analyzer.analysis(for: uri) == nil)
    }

    @Test
    func documentURIRoundTrip() {
        let path = "/tmp/some dir/Foo.kt"
        let uri = DocumentURI.uri(fromPath: path)
        #expect(DocumentURI.path(fromURI: uri) == path)
    }
}
#endif
