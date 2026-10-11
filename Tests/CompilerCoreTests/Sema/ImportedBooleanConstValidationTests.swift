@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedBooleanConstValidationTests {
    @Test(arguments: ["b:0", "b:1", "b:", "b:2", "b:false", "b:garbage", "b:01"], [false, true])
    func onlyCanonicalBooleanMetadataCanInitializeConsumerConst(literal: String, indexed: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at: directory) } }
        let artifact = directory.appendingPathComponent("boolean.kklib")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        try """
        {"formatVersion":1,"moduleName":"BooleanMetadata","metadata":"metadata.bin"}
        """.write(to: artifact.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let record = MetadataRecord(
            kind: .property, fqName: "booleanproducer.ENABLED", typeSignature: "Z",
            constValueLiteral: literal
        )
        let encoder = MetadataEncoder()
        let metadata = indexed ? encoder.serializeIndexed([record]) : encoder.serialize([record])
        try metadata.write(to: artifact.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let source = directory.appendingPathComponent("Consumer.kt")
        try """
        package booleanconsumer
        import booleanproducer.ENABLED
        const val COPIED: Boolean = ENABLED
        """.write(to: source, atomically: true, encoding: .utf8)
        let ctx = makeCompilationContext(
            inputs: [source.path], searchPaths: [artifact.path], includeStdlib: false
        )
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let imported = try #require(sema.symbols.lookup(
            fqName: ["booleanproducer", "ENABLED"].map(ctx.interner.intern)
        ))
        let copied = try #require(sema.symbols.lookup(
            fqName: ["booleanconsumer", "COPIED"].map(ctx.interner.intern)
        ))
        let canonical = literal == "b:0" || literal == "b:1"
        try #require(sema.symbols.symbol(imported)?.flags.contains(.constValue) == canonical)
        if canonical {
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try #require(sema.symbols.constValueExprKind(for: copied) == .boolLiteral(literal == "b:1"))
        } else {
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            try #require(errors.count == 1, "\(errors)")
            try #require(errors.first?.code == "KSWIFTK-SEMA-0083")
            try #require(sema.symbols.constValueExprKind(for: imported) == nil)
            try #require(sema.symbols.constValueExprKind(for: copied) == nil)
        }
        completed = true
    }
}
