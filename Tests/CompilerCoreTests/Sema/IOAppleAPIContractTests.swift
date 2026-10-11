@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct IOAppleAPIContractTests {
    @Test(arguments: [false, true])
    func sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library: Bool) throws {
        if library { TestStdlibCache.shared.prepare() }
        let artifact = library ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data("fun main() = 0".utf8))
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let rows: [(String, String, String)] = [
            ("kotlinx.io.bytestring.toNSData", "Lkotlinx.io.bytestring.ByteString;", "Lplatform.Foundation.NSData;"),
            ("kotlinx.io.bytestring.toByteString", "Lplatform.Foundation.NSData;", "Lkotlinx.io.bytestring.ByteString;"),
            ("kotlinx.io.asSource", "Lplatform.Foundation.NSInputStream;", "Lkotlinx.io.RawSource;"),
            ("kotlinx.io.asSink", "Lplatform.Foundation.NSOutputStream;", "Lkotlinx.io.RawSink;"),
            ("kotlinx.io.asNSInputStream", "Lkotlinx.io.Source;", "Lplatform.Foundation.NSInputStream;"),
            ("kotlinx.io.asNSOutputStream", "Lkotlinx.io.Sink;", "Lplatform.Foundation.NSOutputStream;"),
        ]
        let mangler = NameMangler()
        func encoded(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: sema.symbols, types: sema.types,
                nameResolver: { ctx.interner.resolve($0) }, unboxValueClasses: false)
        }
        var records: [MetadataRecord] = []
        if let artifact {
            let directory = URL(fileURLWithPath: artifact, isDirectory: true)
            let manifest = try #require(JSONSerialization.jsonObject(with:
                Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
            records = MetadataDecoder().decode(try String(contentsOf:
                directory.appendingPathComponent("metadata.bin"), encoding: .utf8))
        }
        for (fqName, receiver, result) in rows {
            let matches = sema.symbols.allSymbols().filter { symbol in
                guard symbol.kind == .function, !symbol.flags.contains(.extensionMemberAlias),
                    symbol.fqName.map(ctx.interner.resolve).joined(separator: ".") == fqName,
                    let signature = sema.symbols.functionSignature(for: symbol.id),
                    let type = signature.receiverType else { return false }
                return encoded(type) == receiver
            }
            let symbol = try #require(matches.count == 1 ? matches.first : nil, "\(fqName): \(matches)")
            let signature = try #require(sema.symbols.functionSignature(for: symbol.id))
            #expect(symbol.visibility == .public)
            #expect(symbol.flags.contains(.importedLibrary) == library)
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.valueParameterHasDefaultValues.isEmpty)
            #expect(encoded(signature.returnType) == result)
            let optIn = sema.symbols.annotations(for: symbol.id).filter { $0.annotationFQName == "kotlin.OptIn" }
            let expectedMarkers: [String]
            switch fqName {
            case "kotlinx.io.bytestring.toNSData":
                expectedMarkers = ["kotlinx.cinterop.UnsafeNumber::class", "kotlinx.cinterop.BetaInteropApi::class", "kotlinx.cinterop.ExperimentalForeignApi::class"]
            case "kotlinx.io.bytestring.toByteString":
                expectedMarkers = ["kotlinx.cinterop.ExperimentalForeignApi::class", "kotlinx.cinterop.UnsafeNumber::class", "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class"]
            default: expectedMarkers = []
            }
            if library || expectedMarkers.isEmpty {
                #expect(optIn.isEmpty, "Exact SOURCE-retention and unannotated function boundary")
            } else {
                try #require(optIn.count == 1)
                let annotation = try #require(optIn.first)
                #expect(annotation.useSiteTarget == nil)
                #expect(annotation.arguments.map(canonicalMarker) == expectedMarkers)
            }
            if library {
                let encodedSignature = mangler.mangledSignature(for: symbol, symbols: sema.symbols, types: sema.types,
                    nameResolver: { ctx.interner.resolve($0) }, unboxValueClasses: false)
                let record = try #require(records.first { $0.kind == .function && $0.fqName == fqName && $0.typeSignature == encodedSignature })
                #expect(record.visibility == .public)
                #expect(record.valueParameterHasDefaultValues.isEmpty)
                #expect(record.annotations.allSatisfy { $0.annotationFQName != "kotlin.OptIn" })
            }
        }
    }

    private func canonicalMarker(_ value: String) -> String {
        let text = value.replacingOccurrences(of: " ", with: "")
        let cinteropMarkers = ["UnsafeNumber", "BetaInteropApi", "ExperimentalForeignApi"]
        for name in cinteropMarkers where text == name + "::class" { return "kotlinx.cinterop." + text }
        if text == "UnsafeByteStringApi::class" { return "kotlinx.io.bytestring.unsafe." + text }
        return text
    }
}
