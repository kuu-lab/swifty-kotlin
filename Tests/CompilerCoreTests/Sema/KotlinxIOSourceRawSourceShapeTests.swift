@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOSourceRawSourceShapeTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let context = makeContextFromSource(
            source,
            moduleName: "KotlinxIOSourceRawSourceShapeProbe",
            emit: .executable,
            allowDefaultStdlibLibrary: library
        )
        #expect((context.options.stdlibLibraryPath != nil) == library)
        try runSema(context)
        return context
    }

    @Test(arguments: [false, true])
    func publicAndParentShapesMatchInSourceAndImportedKlib(library: Bool) throws {
        let source = """
        package kuu2615shape
        import kotlinx.io.Buffer
        import kotlinx.io.RawSource
        import kotlinx.io.Source
        import kotlin.AutoCloseable

        class ExternalRawSource : RawSource {
            override fun readAtMostTo(sink: Buffer, byteCount: Long): Long = -1L
            override fun close() {}
        }

        fun sourceAsRaw(source: Source): RawSource = source
        fun rawAsCloseable(source: RawSource): AutoCloseable = source
        fun closeInherited(value: AutoCloseable) = value.close()
        """
        let context = try context(source, library: library)
        try #require(!context.diagnostics.hasError, "RawSource must allow an external implementation: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let symbols = sema.symbols

        func symbol(_ fqName: String) throws -> SemanticSymbol {
            let components = fqName.split(separator: ".").map { context.interner.intern(String($0)) }
            let id = try #require(symbols.lookup(fqName: components))
            return try #require(symbols.symbol(id))
        }
        func directParents(_ owner: SemanticSymbol) -> Set<String> {
            Set(symbols.directSupertypes(for: owner.id).compactMap { id in
                symbols.symbol(id)?.fqName.map(context.interner.resolve).joined(separator: ".")
            })
        }

        let rawSource = try symbol("kotlinx.io.RawSource")
        let sourceType = try symbol("kotlinx.io.Source")
        let autoCloseable = try symbol("kotlin.AutoCloseable")
        #expect(rawSource.kind == .interface && rawSource.visibility == .public)
        #expect(!rawSource.flags.contains(.sealedType))
        #expect(directParents(rawSource) == ["kotlin.AutoCloseable"])
        #expect(sourceType.kind == .interface && sourceType.visibility == .public)
        #expect(sourceType.flags.contains(.sealedType))
        #expect(directParents(sourceType) == ["kotlinx.io.RawSource"])
        #expect(autoCloseable.kind == .interface && autoCloseable.visibility == .public)

        if library, let path = context.options.stdlibLibraryPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("metadata.bin"))
            let records = MetadataDecoder().decode(data)
            let rawRecord = try #require(records.first { $0.kind == .interface && $0.fqName == "kotlinx.io.RawSource" })
            let sourceRecord = try #require(records.first { $0.kind == .interface && $0.fqName == "kotlinx.io.Source" })
            #expect(rawRecord.visibility == .public && !rawRecord.isSealedClass)
            #expect(rawRecord.superFQName == "kotlin.AutoCloseable")
            #expect(sourceRecord.visibility == .public && sourceRecord.isSealedClass)
            #expect(sourceRecord.superFQName == "kotlinx.io.RawSource")
        }
    }

    @Test(arguments: [false, true])
    func sourceCannotBeImplementedOutsideItsSealedBoundary(library: Bool) throws {
        let source = """
        package kuu2615external
        import kotlinx.io.Source

        class ExternalSource : Source
        """
        let context = try context(source, library: library)
        let errors = context.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0070"
        }
        #expect(errors.count == 1, "Source must reject an external implementation: \(context.diagnostics.diagnostics)")
    }
}
