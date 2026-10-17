@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct UnsafeBufferOperationsShapeTests {
    private struct ShapeIndex: Decodable {
        struct SourceObject: Decodable {
            let declaration: String
            let optIn: String
            let unsafeApi: String
            let upstreamRef: String
        }

        struct JVMClass: Decodable {
            let rowID: String
            let owner: String
            let declaration: String
            let upstreamRef: String
        }

        struct JVMInstanceField: Decodable {
            let rowID: String
            let owner: String
            let name: String
            let descriptor: String
            let modifiers: [String]
            let declaration: String
            let upstreamRef: String
        }

        struct KlibObject: Decodable {
            let rowID: String
            let fqName: String
            let declaration: String
            let annotations: [String]
            let upstreamRef: String
        }

        let schemaVersion: Int
        let upstreamCommit: String
        let sourceObject: SourceObject
        let jvmClass: JVMClass
        let jvmInstanceField: JVMInstanceField
        let klibObject: KlibObject
    }

    private func root() -> URL {
        var result = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { result.deleteLastPathComponent() }
        return result
    }

    private func shape() throws -> ShapeIndex {
        let result = try JSONDecoder().decode(ShapeIndex.self, from: Data(contentsOf:
            root().appendingPathComponent("Scripts/kotlinx_io_upstream/buffer/unsafe-buffer-operations-object-shape.expected.json")))
        try #require(result.schemaVersion == 1)
        try #require(result.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        try #require(result.jvmClass.rowID == "jvm-0cf64a4acbc38a06")
        try #require(result.jvmInstanceField.rowID == "jvm-893b52117cdc6202")
        try #require(result.klibObject.rowID == "klib-0f0ae6b0e4f74922")
        try #require(result.jvmInstanceField.modifiers == ["public", "static", "final"])
        return result
    }

    private func sourceContext(library: Bool) throws -> (CompilationContext, String) {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        if let artifact {
            let directory = URL(fileURLWithPath: artifact, isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                directory.appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        let probePath = root().appendingPathComponent(
            "Scripts/io_api_inventory/probes/UnsafeBufferOperationsObjectShape.kt"
        ).path
        let context = makeCompilationContext(inputs: [probePath], stdlibLibraryPath: artifact,
                                             allowDefaultStdlibLibrary: false)
        let source = try String(contentsOfFile: probePath, encoding: .utf8)
        _ = context.sourceManager.addFile(path: probePath, contents: Data(source.utf8))
        try #require(context.options.includeStdlib == !library)
        try #require(context.options.stdlibLibraryPath == artifact)
        return (context, source)
    }

    @Test
    func pinnedDeclarationMatchesTheThreeDedicatedLedgerRows() throws {
        let expected = try shape()
        let checkout = root()
        let api = try String(contentsOf: checkout.appendingPathComponent(
            "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/core/api/kotlinx-io-core.api"
        ), encoding: .utf8)
        let klibAPI = try String(contentsOf: checkout.appendingPathComponent(
            "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/core/api/kotlinx-io-core.klib.api"
        ), encoding: .utf8)
        let source = try String(contentsOf: checkout.appendingPathComponent(
            "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/core/common/src/unsafe/UnsafeBufferOperations.kt"
        ), encoding: .utf8)
        let ledger = try String(contentsOf: checkout.appendingPathComponent(
            "Scripts/io_api_inventory/api-inventory.tsv"
        ), encoding: .utf8)

        #expect(api.split(separator: "\n").contains(Substring(expected.jvmClass.declaration)))
        #expect(api.split(separator: "\n").contains(Substring(expected.jvmInstanceField.declaration)))
        #expect(klibAPI.split(separator: "\n").contains { $0.hasPrefix(expected.klibObject.declaration) })
        #expect(source.contains(expected.sourceObject.unsafeApi))
        #expect(source.contains(expected.sourceObject.optIn))
        #expect(source.contains(expected.sourceObject.declaration))
        for rowID in [expected.jvmClass.rowID, expected.jvmInstanceField.rowID, expected.klibObject.rowID] {
            #expect(ledger.split(separator: "\n").contains { $0.hasPrefix(rowID + "\t") })
        }
    }

    @Test(arguments: [false, true])
    func objectTypeViewAndKlibSingletonMetadataArePreserved(library: Bool) throws {
        _ = try shape()
        let (context, source) = try sourceContext(library: library)
        try runSema(context)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        #expect(source.contains("value: UnsafeBufferOperations): UnsafeBufferOperations"))

        let sema = try #require(context.sema)
        let symbols = sema.symbols
        let ownerPath = ["kotlinx", "io", "unsafe", "UnsafeBufferOperations"].map { context.interner.intern($0) }
        let ownerID = try #require(symbols.lookup(fqName: ownerPath))
        let owner = try #require(symbols.symbol(ownerID))
        #expect(owner.kind == .object)
        #expect(owner.visibility == .public)
        #expect(owner.flags.contains(.importedLibrary) == library)
        #expect(!owner.flags.contains(.openType) && !owner.flags.contains(.abstractType))

        let preservePath = ["kuu2603", "preserveUnsafeBufferOperations"].map { context.interner.intern($0) }
        let preserveID = try #require(symbols.lookup(fqName: preservePath))
        let preserve = try #require(symbols.symbol(preserveID))
        let signature = try #require(symbols.functionSignature(for: preserve.id))
        #expect(signature.parameterTypes.count == 1)
        for type in signature.parameterTypes + [signature.returnType] {
            guard case let .classType(classType) = sema.types.kind(of: type) else {
                Issue.record("Object type view must remain a nominal class type")
                continue
            }
            #expect(classType.classSymbol == ownerID)
        }

        let objectAnnotations = symbols.annotations(for: ownerID)
        #expect(objectAnnotations.contains { $0.annotationFQName == "kotlinx.io.UnsafeIoApi" })
        if library {
            let artifact = try #require(context.options.stdlibLibraryPath)
            let metadata = MetadataDecoder().decode(try Data(contentsOf:
                URL(fileURLWithPath: artifact, isDirectory: true).appendingPathComponent("metadata.bin")))
            let record = try #require(metadata.first {
                $0.kind == .object && $0.fqName == "kotlinx.io.unsafe.UnsafeBufferOperations"
            })
            #expect(record.visibility == .public && record.modality == .final)
            #expect(record.objectInitializerLinkName?.isEmpty == false)
            #expect(record.annotations.contains { $0.annotationFQName == "kotlinx.io.UnsafeIoApi" })
            #expect(!record.annotations.contains { $0.annotationFQName == "kotlin.OptIn" })
        } else {
            let optIn = objectAnnotations.filter { $0.annotationFQName == "kotlin.OptIn" }
            try #require(optIn.count == 1)
            #expect(optIn[0].arguments.count == 1 && optIn[0].arguments[0].contains("ExperimentalContracts"))
        }
    }
}
