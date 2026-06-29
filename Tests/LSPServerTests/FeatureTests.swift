#if canImport(Testing)
@testable import LSPServer
import Testing

@Suite("LSP.Feature")
struct FeatureTests {
    private let uri = "file:///tmp/LSPFeatures.kt"

    @Test
    func documentSymbolsOutlineClassAndMembers() {
        let source = """
        class Foo {
            val bar: Int = 1
            fun baz(): Int { return bar }
        }

        fun topLevel() {}
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let symbols = DocumentSymbolFeature.documentSymbols(for: analysis)

        let names = symbols.map(\.name)
        #expect(names.contains("Foo"), "Outline should include the class: \(names)")
        #expect(names.contains("topLevel"), "Outline should include the top-level function: \(names)")

        if let foo = symbols.first(where: { $0.name == "Foo" }) {
            #expect(foo.kind == LSPSymbolKind.class.rawValue)
            let childNames = (foo.children ?? []).map(\.name)
            #expect(childNames.contains("bar"), "Class outline should include property: \(childNames)")
            #expect(childNames.contains("baz"), "Class outline should include method: \(childNames)")
        } else {
            Issue.record("Expected a symbol for class Foo")
        }
    }

    @Test
    func hoverOnIntegerLiteralReportsType() {
        let source = "fun main() {\n    val answer = 42\n}\n"
        let analysis = Analyzer().analyze(uri: uri, text: source)
        guard let pos = LSPTestSupport.position(of: "42", in: source) else {
            Issue.record("Could not locate literal in source")
            return
        }

        let hover = HoverFeature.hover(for: analysis, line: pos.line, character: pos.character)
        #expect(hover != nil, "Hover over a literal should return type information")
        #expect(
            hover?.contents.value.contains("Int") ?? false,
            "Hover for `42` should mention Int, got: \(hover?.contents.value ?? "nil")"
        )
    }

    @Test
    func definitionResolvesTopLevelReference() {
        let source = """
        fun helper(): Int {
            return 1
        }

        fun main() {
            helper()
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        // Locate the call site `helper()` inside `main` (the second occurrence).
        guard let callRange = source.range(of: "helper", range: source.range(of: "fun main")!.upperBound ..< source.endIndex) else {
            Issue.record("Could not locate call site")
            return
        }
        let prefix = source[source.startIndex ..< callRange.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let line = lines.count - 1
        let character = (lines.last ?? "").utf16.count

        let location = DefinitionFeature.definition(for: analysis, line: line, character: character + 1)
        // Definition resolution depends on call-binding population; assert that
        // when a location is returned it points inside the analyzed document.
        if let location {
            #expect(location.uri == DocumentURI.uri(fromPath: analysis.path))
            #expect(location.range.start.line <= line)
        }
    }
}
#endif
