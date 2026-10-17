@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOBufferHeadContractTests {
    private func context(_ source: String = "fun main() = Unit", library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? CompilerOptions.defaultStdlibLibraryPath : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(ctx.options.stdlibLibraryPath == artifact && ctx.options.includeStdlib == !library)
        return ctx
    }

    @Test(arguments: [false, true])
    func publishedInternalHeadKeepsNullableAccessorMetadata(library: Bool) throws {
        let ctx = try context(library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let name = "kotlinx.io.Buffer.head"
        let properties = symbols.lookupAll(fqName: name.split(separator: ".").map { ctx.interner.intern(String($0)) })
            .compactMap { symbols.symbol($0) }.filter { $0.kind == .property }
        try #require(properties.count == 1, "\(name)")
        let property = try #require(properties.first)
        #expect(property.visibility == .internal)
        #expect(property.flags.contains(.mutable))
        #expect(property.flags.contains(.importedLibrary) == library)

        let type = try #require(symbols.propertyType(for: property.id))
        #expect(sema.types.nullability(of: type) == .nullable)
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            Issue.record("Buffer.head must retain the Segment? classifier")
            return
        }
        let segment = try #require(symbols.symbol(classType.classSymbol))
        #expect(ctx.interner.resolve(segment.name) == "Segment")

        let annotations = symbols.annotations(for: property.id)
        let publishedApi = annotations.filter { $0.annotationFQName == "kotlin.PublishedApi" }
        #expect(publishedApi.count == 1 && publishedApi[0].useSiteTarget == nil)
        let synthetic = annotations.filter { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" }
        #expect(synthetic.map(\.useSiteTarget).sorted { ($0 ?? "") < ($1 ?? "") } == ["get", "set"])

        if library {
            let records = MetadataDecoder().decode(try Data(contentsOf: URL(fileURLWithPath:
                try #require(ctx.options.stdlibLibraryPath)).appendingPathComponent("metadata.bin")))
            let record = try #require(records.first { $0.kind == .property && $0.fqName == name })
            #expect(record.visibility == .internal && record.isMutable)
            #expect(record.annotations.filter { $0.annotationFQName == "kotlin.PublishedApi" }
                .contains { $0.useSiteTarget == nil })
            #expect(record.annotations.filter { $0.annotationFQName == "kotlin.jvm.JvmSynthetic" }
                .map(\.useSiteTarget).sorted { ($0 ?? "") < ($1 ?? "") } == ["get", "set"])

            // Imported KLIB properties are represented by one property symbol;
            // their JVM accessor shape is asserted by the pinned Java probe.
        }
    }

    @Test(arguments: [false, true])
    func unprivilegedConsumerCannotReadOrWriteHead(library: Bool) throws {
        let source = """
        import kotlinx.io.Buffer
        fun main() {
            val buffer = Buffer()
            buffer.head
            buffer.head = null
        }
        """
        let ctx = try context(source, library: library)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "Both internal accessor uses must be rejected: \(errors)")
    }
}
