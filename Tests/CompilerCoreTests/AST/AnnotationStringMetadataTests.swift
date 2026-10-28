@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct AnnotationStringMetadataTests {
    static let literals: [(String, String)] = [
        (#""isReadOnly""#, "isReadOnly"),
        (#""""#, ""),
        (#""A\nB\t\"C\"\\\$""#, "A\nB\t\"C\"\\$"),
        (#""\uD800""#, decodeKotlinStringEscapes(#"\uD800"#)),
        (#""""A\nB""""#, #"A\nB"#),
        (#""""""""#, ""),
        (#"""" "quoted" """"#, #" "quoted" "#),
        (#"""""leading" end""""#, #""leading" end"#),
        (#"$$"isReadOnly""#, "isReadOnly"),
        (#"$$"""#, ""),
        (#"$$"""A\nB""""#, #"A\nB"#),
        (#"$$"""""""#, ""),
        (#"$$""" "quoted" """"#, #" "quoted" "#),
        (#"$$"literal $name and ${name}""#, "literal $name and ${name}"),
    ]

    @Test(arguments: literals, [false, true])
    func singleLiteralMetadataPreservesExactlyOneDelimiterPair(
        literal: (String, String), named: Bool
    ) throws {
        let prefix = named ? "message=" : ""
        let (tokens, interner, diagnostics) = lex("@Marker(\(prefix)\(literal.0)) class Subject")
        #expect(!diagnostics.hasError)
        let parsed = try #require(AnnotationParsingSupport.parseAnnotation(
            from: tokens, start: 0, interner: interner, allowUseSiteTarget: true
        ))
        #expect(parsed.annotation.arguments == [prefix + literal.0])
        let argument = try #require(parsed.annotation.arguments.first)
        let value = SemaAnnotationArgument.value(argument, parameterName: named ? "message" : nil)
        let extraction = try #require(extractKotlinStringLiteralContent(value))
        let decoded = extraction.isRaw ? extraction.content : decodeKotlinStringEscapes(extraction.content)
        #expect(decoded == literal.1)
    }

    @Test(arguments: [
        #""A" + name"#, #""A${"B"}C""#,
        #"$$"A$${"B"}C""#, #"$$"A$$name B""#,
    ])
    func nonliteralAndTemplateArgumentsKeepTheirTokenBoundaries(expression: String) throws {
        let (tokens, interner, diagnostics) = lex("@Marker(\(expression)) class Subject")
        #expect(!diagnostics.hasError)
        let parsed = try #require(AnnotationParsingSupport.parseAnnotation(
            from: tokens, start: 0, interner: interner, allowUseSiteTarget: true
        ))
        #expect(parsed.annotation.arguments == [expression.replacingOccurrences(of: " + ", with: "+")])
    }

    @Test(arguments: literals)
    func canonicalLiteralDecoderPreservesRawContentQuotes(literal: (String, String)) throws {
        let extraction = try #require(extractKotlinStringLiteralContent(literal.0))
        #expect((extraction.isRaw ? extraction.content : decodeKotlinStringEscapes(extraction.content)) == literal.1)
    }

    @Test(arguments: [
        (#"""abc"""#, "abc", false),
        (#"$$""abc"$$""#, "abc", false),
        (#"$$"$$""#, "", false),
        (#"""""A\nB"""""#, #"A\nB"#, true),
        (#"$$""""A\nB"$$""""#, #"A\nB"#, true),
        (#"$$"""$$""""#, "", true),
    ])
    func legacyTokenTextRequiresExplicitProvenance(value: String, expected: String, isRaw: Bool) throws {
        let extraction = try #require(extractKotlinStringLiteralContent(value, representation: .legacyAnnotationTokens))
        #expect(extraction.content == expected)
        #expect(extraction.isRaw == isRaw)
    }

    @Test
    func identicalQuoteCountsDoNotEraseCanonicalRawContent() throws {
        let text = #"""""quoted"""""#
        let canonical = try #require(extractKotlinStringLiteralContent(text))
        let legacy = try #require(extractKotlinStringLiteralContent(text, representation: .legacyAnnotationTokens))
        #expect(canonical.isRaw && canonical.content == #""quoted""#)
        #expect(legacy.isRaw && legacy.content == "quoted")
    }

    @Test
    func frontendCacheRoundTripsCanonicalAnnotationsAndRejectsVersionFive() throws {
        try withTemporaryFile(contents: """
        class Flags {
            @get:JvmName("isReadOnly")
            val isReadOnly: Boolean get() = true
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontendSyntaxPhases(ctx)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let cache = IncrementalCompilationCache(cachePath: root.path)
            let hash = cache.buildConfigurationHash(for: ctx.options)
            let snapshot = try #require(IncrementalFrontendState(context: ctx, buildConfigurationHash: hash))
            #expect(snapshot.version > 5)
            cache.computeCurrentFingerprints(for: [path])
            cache.saveState(dependencyGraph: DependencyGraph(), options: ctx.options, frontendState: snapshot)
            let current = IncrementalCompilationCache(cachePath: root.path)
            current.loadPreviousState()
            let restored = try #require(current.loadFrontendState(for: ctx.options))
            let annotations = restored.arenaSnapshot.declarations.compactMap { declaration -> [AnnotationNode]? in
                guard case let .propertyDecl(property) = declaration else { return nil }
                return property.annotations
            }.flatMap { $0 }
            #expect(annotations == [AnnotationNode(name: "JvmName", arguments: [#""isReadOnly""#], useSiteTarget: "get")])

            let file = root.appendingPathComponent("frontend.json")
            var old = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            old["version"] = 5
            try JSONSerialization.data(withJSONObject: old).write(to: file)
            try #require(IncrementalCacheTrust.writeIntegrityIndex(cachePath: root.path) != nil)
            let previous = IncrementalCompilationCache(cachePath: root.path)
            previous.loadPreviousState()
            #expect(previous.loadFrontendState(for: ctx.options) == nil)
        }
    }

    @Test(arguments: [false, true])
    func markerFreeLibraryArgumentsAreMigratedBeforeSemanticImport(indexed: Bool) throws {
        let legacy = [
            #"""abc"""#, #""""#, #"$$""abc"$$""#, #"$$"$$""#,
            #"""""A\nB"""""#, #"$$""""A\nB"$$""""#, #"$$"""$$""""#,
            #"message = ""key=value"""#, #"""key=value"""#, "constantName", "'x'",
        ]
        let canonical = [
            #""abc""#, #""""#, #"$$"abc""#, #"$$"""#,
            #""""A\nB""""#, #"$$"""A\nB""""#, #"$$"""""""#,
            #"message="key=value""#, #""key=value""#, "constantName", "'x'",
        ]
        let record = MetadataRecord(kind: .class, mangledName: "Legacy", fqName: "fixture.Legacy", annotations: [
            MetadataAnnotationRecord(annotationFQName: "fixture.Marker", arguments: legacy, useSiteTarget: "get"),
        ])
        let encoder = MetadataEncoder()
        // Build an authentic marker-free body before constructing the index:
        // removing bytes after indexed serialization would invalidate offsets.
        let legacyBody = encoder.serialize([record]).replacingOccurrences(of: "|literalFormat:canonical", with: "")
        let bodyLine = try #require(legacyBody.split(whereSeparator: \.isNewline).last)
        let metadata = indexed
            ? "kklib-metadata-v2\nrecords=1\nindex\n0\t\(bodyLine.utf8.count + 1)\tclass Legacy fq=fixture.Legacy schema=v1\nbody\n\(bodyLine)\n"
            : legacyBody
        let decoded = try #require(MetadataDecoder().decode(metadata).first)
        #expect(decoded.annotations[0].arguments == canonical)
        #expect(decoded.annotations[0].useSiteTarget == "get")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"{"formatVersion":1,"moduleName":"LegacyProducer","metadata":"metadata.bin"}"#.write(
            to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8
        )
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() {}") { path in
            let consumer = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
            try runSema(consumer)
            try #require(!consumer.diagnostics.hasError)
            let sema = try #require(consumer.sema)
            let symbol = try #require(sema.symbols.lookup(fqName: ["fixture", "Legacy"].map(consumer.interner.intern)))
            #expect(sema.symbols.annotations(for: symbol) == decoded.annotations)
        }
    }

    @Test(arguments: [false, true])
    func sourceAnnotationsSurviveMetadataExportAndLibraryImport(indexed: Bool) throws {
        let declarations = Self.literals.enumerated().map { index, literal in
            "@Marker(message = \(literal.0)) class Subject\(index)"
        }.joined(separator: "\n")
        let source = """
        package fixture
        import kotlin.jvm.JvmName
        annotation class Marker(val message: String)
        \(declarations)
        @Marker(message = "isRead" + "Only") class Concatenated
        @Marker(message = CONSTANT) class ConstantReference
        const val CONSTANT: String = "constant"
        class Flags {
            @get:JvmName("isReadOnly")
            val isReadOnly: Boolean
                get() = true
        }
        """
        let producer = makeContextFromSource(source, moduleName: "AnnotationProducer")
        try runSema(producer)
        try #require(!producer.diagnostics.hasError, "\(producer.diagnostics.diagnostics)")
        let sema = try #require(producer.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "AnnotationProducer", interner: producer.interner, functionLinkNames: [:]
        ).filter { $0.fqName.hasPrefix("fixture.") }
        for (index, literal) in Self.literals.enumerated() {
            let record = try #require(records.first { $0.fqName == "fixture.Subject\(index)" })
            #expect(record.annotations.first { $0.annotationFQName == "fixture.Marker" }?.arguments == ["message=" + literal.0])
        }
        let flags = try #require(records.first { $0.fqName == "fixture.Flags.isReadOnly" })
        #expect(flags.annotations == [MetadataAnnotationRecord(
            annotationFQName: "kotlin.jvm.JvmName", arguments: [#""isReadOnly""#], useSiteTarget: "get"
        )])
        let concatenated = try #require(records.first { $0.fqName == "fixture.Concatenated" })
        #expect(concatenated.annotations.first?.arguments == [#"message="\u0069\u0073\u0052\u0065\u0061\u0064\u004f\u006e\u006c\u0079""#])
        let constant = try #require(records.first { $0.fqName == "fixture.ConstantReference" })
        #expect(constant.annotations.first?.arguments == ["message=CONSTANT"])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try #"{"formatVersion":1,"moduleName":"AnnotationProducer","metadata":"metadata.bin"}"#.write(
            to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8
        )
        let metadata = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() {}") { path in
            let consumer = makeCompilationContext(inputs: [path], moduleName: "Consumer", searchPaths: [directory.path])
            try runSema(consumer)
            try #require(!consumer.diagnostics.hasError, "\(consumer.diagnostics.diagnostics)")
            let imported = try #require(consumer.sema)
            for record in records where !record.annotations.isEmpty {
                let symbol = try #require(imported.symbols.lookup(
                    fqName: record.fqName.split(separator: ".").map { consumer.interner.intern(String($0)) }
                ))
                #expect(imported.symbols.symbol(symbol)?.flags.contains(.importedLibrary) == true)
                #expect(imported.symbols.annotations(for: symbol) == record.annotations)
            }
        }
    }
}
