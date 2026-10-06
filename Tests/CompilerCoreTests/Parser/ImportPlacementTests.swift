@testable import CompilerCore
import Testing

@Suite
struct ImportPlacementTests {
    @Test
    func bundledStdlibImportsPrecedeDeclarations() {
        let sources = BundledStdlib.bundledStdlibSources()
        #expect(!sources.isEmpty)
        for source in sources {
            let parsed = parse(String(decoding: source.contents, as: UTF8.self))
            #expect(
                !parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0017" },
                "Import after a declaration in \(source.path)"
            )
        }
    }

    @Test(arguments: [
        "val x = 1",
        "var x = 1",
        "fun before() {}",
        "class Before",
        "interface Before",
        "object Before {}",
        "typealias Before = Int",
        "@Deprecated(\"old\") fun before() {}",
        "context(value: Int) fun before() {}",
        "println(1)",
    ])
    func importAfterFileBodyIsRejected(body: String) throws {
        let source = "\(body)\nimport kotlin.math.PI\nfun after() {}"
        let parsed = parse(source)
        let diagnostic = try #require(parsed.diagnostics.diagnostics.first)

        #expect(parsed.diagnostics.diagnostics.count == 1)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.code == "KSWIFTK-PARSE-0017")
        #expect(diagnostic.message == "Imports are only allowed in the beginning of file.")
        #expect(diagnostic.primaryRange?.start.offset == body.utf8.count + 1)
        #expect(diagnostic.primaryRange?.end.offset == body.utf8.count + 7)
        #expect(parsed.arena.nodes.contains { $0.kind == .funDecl && $0.range.start.offset > body.utf8.count })
    }

    @Test
    func issueReproductionIsRejected() {
        let parsed = parse("""
        package p
        val x = 1
        import kotlin.math.PI
        fun main() { println(x) }
        """)

        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0017"])
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
    }

    @Test(arguments: [
        "val x = 1; import kotlin.math.PI; fun after() {}",
        "import kotlin.math.E\nval x = 1\nimport kotlin.math.PI as circle\nfun after() {}",
        "class Before\nimport kotlin.math.*\nfun after() {}",
        "val x = 1\n@file:Suppress(\"unused\")\nimport kotlin.math.PI\nfun after() {}",
    ])
    func importVariantsAfterDeclarationsAreRejected(source: String) {
        let parsed = parse(source)
        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0017"])
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
    }

    @Test
    func everyLateImportIsDiagnosed() {
        let parsed = parse("""
        val x = 1
        import kotlin.math.PI
        import kotlin.math.E as e
        import kotlin.math.*
        fun after() {}
        """)

        #expect(parsed.diagnostics.diagnostics.map(\.code) == Array(repeating: "KSWIFTK-PARSE-0017", count: 3))
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
    }

    @Test(arguments: [
        "",
        "package p\n",
        "@file:Suppress(\"unused\")\n",
        "@file:Suppress(\"unused\")\npackage p\n",
    ])
    func importsBeforeDeclarationsRemainValid(header: String) {
        let parsed = parse("""
        \(header)import kotlin.math.PI
        import kotlin.math.E as e
        import kotlin.math.*
        val x = 1
        fun main() { println(x) }
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .importHeader } == 3)
        #expect(parsed.arena.nodes.count { $0.kind == .importList } == 1)
    }

    @Test
    func scriptImportsBeforeStatementsRemainValid() {
        let parsed = parse("import kotlin.math.PI\nprintln(PI)")
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .script)
    }
}
