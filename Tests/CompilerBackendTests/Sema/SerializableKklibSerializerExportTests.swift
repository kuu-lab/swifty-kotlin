#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct SerializableKklibSerializerExportTests {
    private let serializationStubSource = """
    package kotlinx.serialization

    annotation class Serializable

    interface KSerializer<T>
    """

    private let librarySource = """
    package demo

    import kotlinx.serialization.Serializable

    @Serializable
    class D(val x: Int)
    """

    private let nestedLibrarySource = """
    package demo

    import kotlinx.serialization.Serializable

    class Outer {
        @Serializable
        class Nested(val x: Int)
    }

    @Serializable
    object O
    """

    private let consumerSource = """
    package demo.consumer

    import demo.D

    fun useSerializer() {
        val serializer = D.serializer()
    }
    """

    @Test
    func companionSerializerSurvivesLibraryMetadataExport() throws {
        try withTemporaryFiles(contents: [serializationStubSource, librarySource]) { libraryPaths in
            let libraryCtx = CompilerTestSupport.makeCompilationContext(
                inputs: libraryPaths,
                moduleName: "SerialLib",
                emit: .kirDump,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(libraryCtx)
            let sema = try #require(libraryCtx.sema)
            let functionLinkNames = sema.serializationClasses.values.reduce(into: [SymbolID: String]()) { result, info in
                if let serializer = info.companionSerializerMethod {
                    result[serializer] = "kk_serializer"
                }
            }

            let records = MetadataEncoder().buildRecords(
                symbols: sema.symbols,
                types: sema.types,
                moduleName: "SerialLib",
                interner: libraryCtx.interner,
                functionLinkNames: functionLinkNames,
                includeSynthetic: false,
                serializationClasses: sema.serializationClasses
            )
            let serializerRecord = try #require(records.first { $0.fqName == "demo.D.Companion.serializer" })
            #expect(serializerRecord.kind == .function)
            #expect(records.contains { $0.fqName == "demo.D.Companion" && $0.kind == .object })

            let libraryDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("kklib")
            try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: libraryDir) }
            try #"{"formatVersion":1,"moduleName":"SerialLib","metadata":"metadata.bin"}"#
                .write(to: libraryDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try MetadataEncoder().serializeCompactIndexed(records)
                .write(to: libraryDir.appendingPathComponent("metadata.bin"))

            try withTemporaryFile(contents: consumerSource) { consumerPath in
                let consumerCtx = CompilerTestSupport.makeCompilationContext(
                    inputs: [consumerPath],
                    moduleName: "SerialConsumer",
                    emit: .kirDump,
                    searchPaths: [libraryDir.path],
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                )
                try runSema(consumerCtx)

                #expect(!consumerCtx.diagnostics.hasError, "Unexpected errors: \(consumerCtx.diagnostics.diagnostics)")
                let importedSerializer = try #require(consumerCtx.sema?.symbols.lookupAll(
                    fqName: ["demo", "D", "Companion", "serializer"].map(consumerCtx.interner.intern)
                ).compactMap { consumerCtx.sema?.symbols.symbol($0) }.first {
                    $0.kind == .function && $0.flags.contains(.importedLibrary)
                })
                #expect(importedSerializer.fqName.map { consumerCtx.interner.resolve($0) }.joined(separator: ".") == "demo.D.Companion.serializer")
            }
        }
    }

    @Test
    func unloweredSerializationMembersAreNotExported() throws {
        try withTemporaryFiles(contents: [serializationStubSource, nestedLibrarySource]) { libraryPaths in
            let libraryCtx = CompilerTestSupport.makeCompilationContext(
                inputs: libraryPaths,
                moduleName: "SerialLib",
                emit: .kirDump,
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(libraryCtx)
            let sema = try #require(libraryCtx.sema)
            #expect(sema.serializationClasses.count >= 2)

            let records = MetadataEncoder().buildRecords(
                symbols: sema.symbols,
                types: sema.types,
                moduleName: "SerialLib",
                interner: libraryCtx.interner,
                functionLinkNames: [:],
                includeSynthetic: false,
                serializationClasses: sema.serializationClasses
            )

            #expect(!records.contains { $0.fqName == "demo.Outer.Nested.Companion.serializer" })
            #expect(!records.contains { $0.fqName == "demo.O.Companion.serializer" })
            #expect(!records.contains { $0.fqName == "demo.O.Companion" && $0.kind == .object })
        }
    }
}
#endif
