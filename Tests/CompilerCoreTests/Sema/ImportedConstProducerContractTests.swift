#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// Records come from real Kotlin producer Sema and the production encoder.
// This Core test is not a claim of native-object producer/link validation.
@Suite
struct ImportedConstProducerContractTests {
    @Test(arguments: [false, true])
    func producerConstContractSurvivesConsumerImport(indexed: Bool) throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? fm.removeItem(at: base) } }
        let producerPath = base.appendingPathComponent("Producer.kt")
        try """
        package constantproducer
        class Capacity {
            companion object {
                const val SIZE: Int = 8192
                val ordinary: Int = 8192
            }
        }
        """.write(to: producerPath, atomically: true, encoding: .utf8)
        let producer = makeCompilationContext(
            inputs: [producerPath.path], moduleName: "ConstProducer", includeStdlib: false
        )
        try runSema(producer)
        try #require(!producer.diagnostics.hasError, "\(producer.diagnostics.diagnostics)")
        let producerSema = try #require(producer.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: producerSema.symbols, types: producerSema.types,
            moduleName: "ConstProducer", interner: producer.interner, functionLinkNames: [:]
        ).filter { $0.fqName == "constantproducer" || $0.fqName.hasPrefix("constantproducer.") }
        let constant = try #require(records.first { $0.fqName == "constantproducer.Capacity.Companion.SIZE" })
        let ordinary = try #require(records.first { $0.fqName == "constantproducer.Capacity.Companion.ordinary" })
        try #require(constant.constValueLiteral == "i:8192")
        try #require(ordinary.constValueLiteral == nil)

        let artifact = base.appendingPathComponent("producer.kklib")
        try fm.createDirectory(at: artifact, withIntermediateDirectories: true)
        try """
        {"formatVersion":1,"moduleName":"ConstProducer","metadata":"metadata.bin"}
        """.write(to: artifact.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let metadata = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try metadata.write(to: artifact.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        let positivePath = base.appendingPathComponent("Positive.kt")
        try """
        package constantconsumer
        import constantproducer.Capacity
        const val COPIED = Capacity.SIZE
        fun ordinaryValue(): Int = Capacity.ordinary
        """.write(to: positivePath, atomically: true, encoding: .utf8)
        let positive = makeCompilationContext(
            inputs: [positivePath.path], moduleName: "ConstConsumer",
            searchPaths: [artifact.path], includeStdlib: false
        )
        try runSema(positive)
        try #require(!positive.diagnostics.hasError, "\(positive.diagnostics.diagnostics)")
        let sema = try #require(positive.sema)
        let imported = try #require(sema.symbols.lookup(
            fqName: ["constantproducer", "Capacity", "Companion", "SIZE"].map(positive.interner.intern)
        ))
        try #require(sema.symbols.symbol(imported)?.flags.contains(.constValue) == true)
        try #require(sema.symbols.constValueExprKind(for: imported) == .intLiteral(8192))
        let copied = try #require(sema.symbols.lookup(
            fqName: ["constantconsumer", "COPIED"].map(positive.interner.intern)
        ))
        try #require(sema.symbols.constValueExprKind(for: copied) == .intLiteral(8192))
        let ordinaryImported = try #require(sema.symbols.lookup(
            fqName: ["constantproducer", "Capacity", "Companion", "ordinary"].map(positive.interner.intern)
        ))
        try #require(sema.symbols.symbol(ordinaryImported)?.flags.contains(.constValue) == false)
        try #require(sema.symbols.constValueExprKind(for: ordinaryImported) == nil)

        let negativePath = base.appendingPathComponent("Negative.kt")
        try """
        package invalidconsumer
        import constantproducer.Capacity
        const val NOT_CONSTANT = Capacity.ordinary
        """.write(to: negativePath, atomically: true, encoding: .utf8)
        let negative = makeCompilationContext(
            inputs: [negativePath.path], moduleName: "NegativeConsumer",
            searchPaths: [artifact.path], includeStdlib: false
        )
        try runSema(negative)
        let errors = negative.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.count == 1, "\(errors)")
        try #require(errors.first?.code == "KSWIFTK-SEMA-0083")
        let negativeSema = try #require(negative.sema)
        let invalid = try #require(negativeSema.symbols.lookup(
            fqName: ["invalidconsumer", "NOT_CONSTANT"].map(negative.interner.intern)
        ))
        try #require(negativeSema.symbols.constValueExprKind(for: invalid) == nil)
        completed = true
    }
}
#endif
