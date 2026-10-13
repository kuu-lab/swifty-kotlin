@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct AnnotationRetentionMetadataTests {
    @Test
    func optionalRetentionMetadataRoundTripsAlongsideLegacyRecords() throws {
        let annotations = [
            MetadataAnnotationRecord(annotationFQName: "Legacy"),
            MetadataAnnotationRecord(annotationFQName: "Hidden", arguments: ["value=1"], useSiteTarget: "field", retention: .binary),
        ]
        let encoder = MetadataEncoder()
        let decoded = MetadataDecoder().decode(encoder.serialize([
            MetadataRecord(kind: .class, fqName: "Tagged", annotations: annotations),
        ]))
        #expect(decoded.first?.annotations == annotations)
    }

    @Test
    func exportPreservesBinaryAndCanonicalizesProducerAliases() throws {
        TestStdlibCache.shared.prepare()
        let source = """
        import kotlin.annotation.Retention as Keep
        import kotlin.annotation.AnnotationRetention.BINARY as Bin
        import kotlin.annotation.AnnotationRetention.SOURCE as SourceOnly
        @Keep(((SourceOnly))) annotation class SourceMark
        @Keep(value = (Bin)) annotation class BinaryMark
        @Keep(Bin) private annotation class Hidden
        annotation class DefaultMark
        @SourceMark @BinaryMark @DefaultMark @Hidden class Tagged
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let tagged = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Tagged")]))
            let sourceAnnotations = sema.symbols.annotations(for: tagged)
            #expect(Set(sourceAnnotations.map(\.annotationFQName)) == ["SourceMark", "BinaryMark", "DefaultMark", "Hidden", "kotlin.Metadata"])
            let encoder = MetadataEncoder()
            let records = encoder.buildRecords(
                symbols: sema.symbols, types: sema.types, moduleName: "RetentionProducer",
                interner: context.interner, functionLinkNames: [:]
            )
            let decoded = MetadataDecoder().decode(encoder.serialize(records))
            let exported = try #require(decoded.first { $0.fqName == "Tagged" })
            #expect(Set(exported.annotations.map(\.annotationFQName)) == ["BinaryMark", "DefaultMark", "Hidden", "kotlin.Metadata"])
            #expect(!decoded.contains { $0.fqName == "Hidden" })
            let hidden = try #require(exported.annotations.first { $0.annotationFQName == "Hidden" })
            #expect(hidden.retention == .binary)
            #expect(resolvedAnnotationRetention(hidden, symbols: SymbolTable(), interner: context.interner) == .binary)
            let binary = try #require(decoded.first { $0.fqName == "BinaryMark" })
            let retention = try #require(binary.annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" })
            #expect(retention.arguments.count == 1)
            #expect(retention.arguments.first?.hasSuffix("kotlin.annotation.AnnotationRetention.BINARY") == true)
            #expect(exported.annotations.first { $0.annotationFQName == "BinaryMark" }?.retention == .binary)
        }
    }

    @Test
    func nestedClassifiersPrecedeImportsAndRootPackages() throws {
        TestStdlibCache.shared.prepare()
        let root = """
        package Holder
        @Retention(AnnotationRetention.BINARY) annotation class Mark
        """
        let imported = """
        package other
        @Retention(AnnotationRetention.BINARY) annotation class Mark
        """
        let source = """
        package p
        import other.Mark
        import kotlin.annotation.AnnotationRetention.BINARY as RUNTIME
        class Holder { annotation class Mark }
        @Holder.Mark class Relative
        class Shadow {
            @Mark class Tagged
            annotation class Mark
        }
        @Retention(AnnotationRetention.RUNTIME) annotation class Visible
        @Visible class RuntimeTagged
        """
        try withTemporaryFiles(contents: [root, imported, source]) { paths in
            let context = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: true)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            for (name, annotation) in [("p.Relative", "p.Holder.Mark"), ("p.Shadow.Tagged", "p.Shadow.Mark"), ("p.RuntimeTagged", "p.Visible")] {
                let symbol = try #require(sema.symbols.lookup(fqName: name.split(separator: ".").map { context.interner.intern(String($0)) }))
                let metadata = try #require(sema.symbols.annotations(for: symbol).first)
                #expect(metadata.annotationFQName == annotation)
                #expect(resolvedAnnotationRetention(metadata, symbols: sema.symbols, interner: context.interner) == .runtime)
            }
        }
    }
}
