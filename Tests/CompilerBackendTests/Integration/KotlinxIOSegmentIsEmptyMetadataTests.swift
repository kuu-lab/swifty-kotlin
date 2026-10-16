@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOSegmentIsEmptyMetadataTests {
    @Test
    func freshStdlibKlibRetainsPublishedInternalPredicateShape() throws {
        let externalLibraryPath = ProcessInfo.processInfo.environment["KSWIFTK_TEST_STDLIB_KLIB"]
        let libraryPath: String
        if let externalLibraryPath {
            libraryPath = externalLibraryPath
        } else {
            TestStdlibCache.shared.prepare()
            libraryPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let library = URL(fileURLWithPath: libraryPath, isDirectory: true)
        let manifest = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: library.appendingPathComponent("manifest.json"))
        ) as? [String: Any])
        try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
        try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
        if externalLibraryPath == nil {
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }

        let metadata = try Data(contentsOf: library.appendingPathComponent("metadata.bin"))
        let records = MetadataDecoder().decode(metadata)
        let matches = records.filter { $0.kind == .function && $0.fqName == "kotlinx.io.isEmpty" }
        let record = try #require(matches.count == 1 ? matches.first : nil)
        try #require(record.visibility == .internal)
        try #require(record.receiverOwnerFQName == "kotlinx.io.Segment")
        try #require(record.arity == 0)
        try #require(record.typeSignature == "F0<RLkotlinx.io.Segment;,Z>")
        try #require(record.annotations.contains { $0.annotationFQName == "kotlin.PublishedApi" })
    }
}
