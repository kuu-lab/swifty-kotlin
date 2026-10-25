#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibTemplateTests {
    private static let layoutTemplate = """
    // Ordinary comments may precede the directives.
    //@ file Ints Int Long
    //@ file Small Byte
    //@ header
    package p

    //@ body
    //@ note notes are dropped from every output
    fun {{T}}Array.a() = 1

    //@ only Int
    fun IntOnly() = 1
    //@ else
    fun {{T}}Else() = 2
    //@ end

    //@ except Long Byte
    fun notLongOrByte() = 3
    //@ end

    """

    private func expand(_ template: String) throws -> [(path: String, text: String)] {
        try BundledStdlibTemplate.expand(Data(template.utf8), at: "kotlin/x/Foo.kt.tmpl")
            .map { (path: $0.relativePath, text: String(decoding: $0.contents, as: UTF8.self)) }
    }

    private func withStdlibResources(_ files: [String: String], _ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSwiftKTemplate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, contents) in files {
            let url = root.appendingPathComponent("Stdlib/\(path)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        try body(root.path)
    }

    @Test
    func testExpandStampsBodyPerTypeAndAppliesConditionals() throws {
        let outputs = try expand(Self.layoutTemplate)
        #expect(outputs.map(\.path) == ["kotlin/x/Ints", "kotlin/x/Small"])
        // Header verbatim, per-type bodies without trailing blanks joined by one
        // blank line, one final newline; `else` and `except` select per type.
        #expect(outputs[0].text == """
        package p

        fun IntArray.a() = 1

        fun IntOnly() = 1

        fun notLongOrByte() = 3

        fun LongArray.a() = 1

        fun LongElse() = 2

        """)
        #expect(outputs[1].text == "package p\n\nfun ByteArray.a() = 1\n\nfun ByteElse() = 2\n")
    }

    @Test
    func testExpandIsDeterministic() throws {
        let first = try expand(Self.layoutTemplate)
        let second = try expand(Self.layoutTemplate)
        #expect(first.map(\.path) == second.map(\.path))
        #expect(first.map(\.text) == second.map(\.text))
    }

    @Test
    func testExpandRejectsMalformedTemplates() {
        let prelude = "//@ file A Int\n//@ header\n//@ body\n"
        let cases: [(template: String, reason: String)] = [
            ("//@ header\n//@ body\n", "before any //@ file"),
            ("fun x() = 1\n", "expected a //@ directive"),
            ("//@ file A Int\n//@ header\n", "missing //@ file, //@ header or //@ body"),
            ("//@ file A Int\n//@ file A Long\n//@ body\n", "duplicate output A"),
            ("//@ file a/b Int\n//@ body\n", "usage: //@ file"),
            (prelude + "//@ nope\n", "unexpected directive //@ nope"),
            (prelude + "//@ only Short\n//@ end\n", "needs Types declared by //@ file"),
            (prelude + "//@ only Int\n//@ except Int\n", "conditionals do not nest"),
            (prelude + "//@ else\n", "unexpected //@ else"),
            (prelude + "//@ end\n", "unexpected //@ end"),
            (prelude + "//@ only Int\nfun x() = 1\n", "unterminated"),
            (prelude + "fun {{t}}() = 1\n", "unknown placeholder"),
        ]
        for (template, reason) in cases {
            do {
                _ = try expand(template)
                Issue.record("Expected failure containing '\(reason)'")
            } catch {
                #expect(String(describing: error).contains(reason), "\(reason) not in \(error)")
            }
        }
    }

    @Test
    func testCollectInjectsTemplateOutputsAtTheirSortedVirtualPaths() throws {
        let files = [
            "kotlin/x/Gamma.kt": "package kotlin.x\n",
            "kotlin/x/Foo.kt.tmpl": "//@ file Beta Int\n//@ file Alpha Long\n//@ header\npackage kotlin.x\n\n//@ body\nval {{T}}Value = 1\n",
        ]
        try withStdlibResources(files) { root in
            let sources = try BundledStdlib.collectBundledStdlibSources(resourcePath: root)
            #expect(sources.map(\.path) == [
                "__bundled_kotlin/x/Alpha.kt",
                "__bundled_kotlin/x/Beta.kt",
                "__bundled_kotlin/x/Gamma.kt",
            ])
            #expect(String(decoding: sources[0].contents, as: UTF8.self) == "package kotlin.x\n\nval LongValue = 1\n")
        }
    }

    @Test
    func testCollectAppliesStdlibProfileToExpandedPackage() throws {
        let files = ["kotlinx/coroutines/Foo.kt.tmpl": "//@ file Bar Int\n//@ header\npackage kotlinx.coroutines\n\n//@ body\nval x = 1\n"]
        try withStdlibResources(files) { root in
            let full = try BundledStdlib.collectBundledStdlibSources(resourcePath: root, profile: .full)
            let minimal = try BundledStdlib.collectBundledStdlibSources(resourcePath: root, profile: .minimal)
            #expect(full.count == 1)
            #expect(minimal.isEmpty)
        }
    }

    @Test
    func testCollectRejectsOutputCollidingWithRealSource() throws {
        let files = [
            "kotlin/x/Bar.kt": "package kotlin.x\n",
            "kotlin/x/Foo.kt.tmpl": "//@ file Bar Int\n//@ header\n//@ body\nval x = 1\n",
        ]
        try withStdlibResources(files) { root in
            #expect(throws: BundledStdlib.LoadError.self) {
                try BundledStdlib.collectBundledStdlibSources(resourcePath: root)
            }
        }
    }

    /// `PrimitiveArrayHOF.kt.tmpl` replaced six hand-written files. Their virtual
    /// paths fix declaration order (hence SymbolIDs and goldens), and the drift
    /// between element types was carried over verbatim: normalizing it changes
    /// behavior and belongs in a separate change with diff cases.
    @Test
    func testPrimitiveArrayHOFTemplateKeepsSixPathsAndDrift() throws {
        let sources = try BundledStdlib.collectBundledStdlibSources()
        let names = ["", "+ByteShort", "+DoubleFloat", "+BooleanChar", "+UByteUShort", "+UIntULong"]
        let paths = names.map { "__bundled_kotlin/collections/PrimitiveArrayHOF\($0).kt" }
        #expect(sources.map(\.path).filter { $0.contains("PrimitiveArrayHOF") } == paths.sorted())
        func text(_ index: Int) throws -> String {
            let source = try #require(sources.first { $0.path == paths[index] })
            return String(decoding: source.contents, as: UTF8.self)
        }
        let ints = try text(0), bytes = try text(1), unsignedSmall = try text(4), unsignedWide = try text(5)
        // Only IntArray.forEach is inline, and only IntArray has scanIndexed.
        #expect(ints.contains("public inline fun IntArray.forEach("))
        #expect(ints.contains("public fun LongArray.forEach(") && bytes.contains("public fun ByteArray.forEach("))
        #expect(ints.contains("IntArray.scanIndexed(") && !ints.contains("LongArray.scanIndexed("))
        // IntArray.map alone has no blank line before mapIndexed.
        #expect(ints.contains("}\npublic fun <R> IntArray.mapIndexed("))
        #expect(ints.contains("}\n\npublic fun <R> LongArray.mapIndexed("))
        // Unsigned arrays carry extra accessors; UInt alone has six more.
        #expect(unsignedSmall.contains("UByteArray.elementAt(") && !unsignedSmall.contains("UByteArray.forEachIndexed("))
        #expect(unsignedWide.contains("UIntArray.forEachIndexed(") && unsignedWide.contains("UIntArray.maxOrNull("))
        #expect(unsignedWide.contains("public fun UIntArray.max(): UInt") && unsignedWide.contains("public fun UIntArray.min(): UInt"))
        #expect(!unsignedWide.contains("public fun ULongArray.max()") && !unsignedWide.contains("public fun ULongArray.min()"))
        #expect(unsignedWide.contains("ULongArray.elementAt(") && !unsignedWide.contains("ULongArray.indexOf("))
    }

    /// `PrimitiveArrayCollectionOps.kt.tmpl` replaced one hand-written file of
    /// eight identical per-type blocks. The cross-type toSortedSet trailer rides on
    /// the last (Double) body verbatim, directly after its closing brace.
    @Test
    func testPrimitiveArrayCollectionOpsTemplateKeepsPathAndTrailer() throws {
        let sources = try BundledStdlib.collectBundledStdlibSources()
        let path = "__bundled_kotlin/collections/PrimitiveArrayCollectionOps.kt"
        #expect(sources.map(\.path).filter { $0.contains("PrimitiveArrayCollectionOps") } == [path])
        let source = try #require(sources.first { $0.path == path })
        let text = String(decoding: source.contents, as: UTF8.self)
        let types = ["Int", "Long", "Byte", "Short", "Char", "Boolean", "Float", "Double"]
        let blockStarts = types.compactMap { text.range(of: "public fun \($0)Array.toHashSet(")?.lowerBound }
        #expect(blockStarts.count == types.count && blockStarts == blockStarts.sorted())
        #expect(text.contains("}\n// Natural ordering only (JVM parity)"))
        #expect(text.components(separatedBy: "Array.toSortedSet(").count - 1 == types.count)
        #expect(text.hasSuffix("public fun CharArray.toSortedSet(): java.util.SortedSet<Char> = asList().toSortedSet()\n"))
    }

    @Test
    func testBrokenTemplateEmits0102AndThrows() throws {
        try withStdlibResources(["kotlin/x/Foo.kt.tmpl": "//@ body\n"]) { root in
            let ctx = makeCompilationContext(inputs: [])
            #expect(throws: (any Error).self) {
                try LoadSourcesPhase().injectBundledStdlib(into: ctx, resourcePath: root)
            }
            assertHasDiagnostic("KSWIFTK-SOURCE-0102", in: ctx)
        }
    }
}
#endif
