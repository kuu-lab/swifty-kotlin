#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct UnsafeByteStringOperationsShapeTests {
    private let fqName = "kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations"
    private let apiMarker = "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi"

    @Test(arguments: [false, true])
    func independentConsumerSeesPublicObjectInSourceAndKlib(library: Bool) throws {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let source = """
        @file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

        package kuu2582.consumer

        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        fun typedSingleton(): UnsafeByteStringOperations = UnsafeByteStringOperations
        fun erasedSingleton(): Any = UnsafeByteStringOperations
        """
        let context = makeCompilationContext(
            inputs: [inputPath],
            moduleName: "KUU2582UnsafeByteStringOperationsConsumer",
            emit: .executable,
            stdlibLibraryPath: artifact,
            allowDefaultStdlibLibrary: false
        )
        #expect(context.options.stdlibLibraryPath == artifact)
        #expect(context.options.includeStdlib == !library)
        _ = context.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        try runSema(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

        let sema = try #require(context.sema)
        let owner = try #require(sema.symbols.lookupAll(
            fqName: fqName.split(separator: ".").map { context.interner.intern(String($0)) }
        ).compactMap { sema.symbols.symbol($0) }.first { $0.kind == .object })
        #expect(owner.visibility == .public)
        #expect(sema.symbols.annotations(for: owner.id).contains {
            $0.annotationFQName == apiMarker
        })

        let typedConsumer = try #require(sema.symbols.lookupAll(
            fqName: ["kuu2582", "consumer", "typedSingleton"].map { context.interner.intern($0) }
        ).compactMap { sema.symbols.symbol($0) }.first { $0.kind == .function })
        #expect(sema.symbols.functionSignature(for: typedConsumer.id) != nil)

        guard library, let artifact else { return }
        let directory = URL(fileURLWithPath: artifact, isDirectory: true)
        let records = MetadataDecoder().decode(try Data(contentsOf: directory.appendingPathComponent("metadata.bin")))
        let objectRecords = records.filter {
            $0.kind == .object && $0.fqName == fqName
        }
        let record = try #require(objectRecords.first, "Missing imported object metadata for \(fqName)")
        #expect(objectRecords.count == 1)
        #expect(record.visibility == .public)
        #expect(record.annotations.contains { $0.annotationFQName == apiMarker })
        #expect(record.objectInitializerLinkName?.isEmpty == false)
        #expect(record.objectLazyInitializerLinkName?.isEmpty == false)
    }
}
#endif
