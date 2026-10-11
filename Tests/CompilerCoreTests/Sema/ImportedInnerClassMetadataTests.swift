#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedInnerClassMetadataTests {
    private func producerRecords() throws -> (records: [MetadataRecord], outerOffset: Int) {
        var result: (records: [MetadataRecord], outerOffset: Int)?
        try withTemporaryFile(contents: """
        package importedinner
        open class Parent(val marker: Int)
        class Outer {
            inner class Inner : Parent(7)
            class Nested
            private val hidden = 9
        }
        enum class EnumOuter {
            VALUE;
            inner class Inner
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "InnerProducer", includeStdlib: false)
            try runSema(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let inner = try #require(sema.symbols.lookup(fqName:
                ["importedinner", "Outer", "Inner"].map(ctx.interner.intern)))
            let field = try #require(sema.symbols.outerInstanceFieldSymbol(for: inner))
            let offset = try #require(sema.symbols.nominalLayout(for: inner)?.fieldOffsets[field])
            // A base-class field precedes $outer; the importer cannot assume slot 2.
            try #require(offset > 2)
            result = (MetadataEncoder().buildRecords(
                symbols: sema.symbols, types: sema.types, moduleName: "InnerProducer", interner: ctx.interner,
                functionLinkNames: [:], includeNonPublic: false, includeSynthetic: false
            ), offset)
        }
        return try #require(result)
    }

    private func writeMetadata(_ records: [MetadataRecord], indexed: Bool, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{\"formatVersion\":1,\"moduleName\":\"InnerProducer\",\"metadata\":\"metadata.bin\"}"
            .write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let encoder = MetadataEncoder()
        let text = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try text.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
    }

    @Test(arguments: [false, true])
    func innerFlagPrivateStorageAndConstructorCallSurviveImport(indexed: Bool) throws {
        let producer = try producerRecords()
        let record = try #require(producer.records.first { $0.fqName == "importedinner.Outer.Inner" })
        try #require(record.isInnerClass)
        try #require(record.fieldOffsets?.contains("importedinner.Outer.Inner.$outer@\(producer.outerOffset)") == true)
        try #require(!producer.records.contains { $0.fqName.hasSuffix(".$outer") || $0.fqName == "importedinner.Outer.hidden" })
        let ctor = try #require(producer.records.first { $0.fqName == "importedinner.Outer.Inner.<init>" })
        try #require(ctor.arity == 0 && ctor.valueParameterNames.isEmpty)
        let encoder = MetadataEncoder()
        let decoded = MetadataDecoder().decode(indexed ? encoder.serializeIndexed(producer.records) : encoder.serialize(producer.records))
        try #require(decoded.first { $0.fqName == record.fqName }?.isInnerClass == true)
        if indexed {
            let file = try #require(IndexedMetadataFile(data: Data(encoder.serializeIndexed(producer.records).utf8)))
            // Member constructor discovery reads the compact symbol before its body.
            try #require(file.entries.first { $0.record.fqName == record.fqName }?.record.isInnerClass == true)
        }
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        defer { try? FileManager.default.removeItem(at: library) }
        try writeMetadata(producer.records, indexed: indexed, directory: library)
        try withTemporaryFile(contents: "import importedinner.*\nfun main() { Outer().Inner() }\nfun fromEnum(value: EnumOuter): EnumOuter.Inner = value.Inner()") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [library.path], includeStdlib: false)
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let inner = try #require(sema.symbols.lookup(fqName:
                ["importedinner", "Outer", "Inner"].map(ctx.interner.intern)))
            try #require(sema.symbols.symbol(inner)?.flags.contains(.innerClass) == true)
            // Querying this map must materialize a lazy nominal before returning.
            let field = try #require(sema.symbols.outerInstanceFieldSymbol(for: inner))
            try #require(sema.symbols.symbol(field)?.visibility == .private)
            try #require(sema.symbols.parentSymbol(for: field) == inner)
            try #require(sema.symbols.propertyType(for: field) != nil)
            try #require(sema.symbols.nominalLayout(for: inner)?.fieldOffsets[field] == producer.outerOffset)
            let constructor = try #require(sema.symbols.lookup(fqName:
                ["importedinner", "Outer", "Inner", "<init>"].map(ctx.interner.intern)))
            try #require(sema.symbols.functionSignature(for: constructor)?.parameterTypes.isEmpty == true)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let store = try #require(kirCalls(to: .arraySet, in: body, interner: ctx.interner).first { call in
                guard call.arguments.count == 3,
                      case let .intLiteral(offset)? = module.arena.expr(call.arguments[1]) else { return false }
                return offset == Int64(producer.outerOffset)
            })
            let call = try #require(kirCalls(to: constructor, in: body).first)
            try #require(store.index < call.index)
            try #require(call.arguments.count == 1 && call.arguments.first == store.arguments.first)
            try #require(store.arguments[0] != store.arguments[2])

            // Kotlin permits an enum enclosing instance as well as a class.
            let enumInner = try #require(sema.symbols.lookup(fqName:
                ["importedinner", "EnumOuter", "Inner"].map(ctx.interner.intern)))
            let enumField = try #require(sema.symbols.outerInstanceFieldSymbol(for: enumInner))
            let enumOwner = try #require(sema.symbols.parentSymbol(for: enumInner))
            try #require(sema.symbols.symbol(enumOwner)?.kind == .enumClass)
            try #require(sema.symbols.symbol(enumField)?.visibility == .private)
            let enumOffset = try #require(sema.symbols.nominalLayout(for: enumInner)?.fieldOffsets[enumField])
            let enumConstructor = try #require(sema.symbols.lookup(fqName:
                ["importedinner", "EnumOuter", "Inner", "<init>"].map(ctx.interner.intern)))
            let enumBody = try findKIRFunctionBody(named: "fromEnum", in: module, interner: ctx.interner)
            let enumStore = try #require(kirCalls(to: .arraySet, in: enumBody, interner: ctx.interner).first { call in
                guard call.arguments.count == 3,
                      case let .intLiteral(offset)? = module.arena.expr(call.arguments[1]) else { return false }
                return offset == Int64(enumOffset)
            })
            let enumCall = try #require(kirCalls(to: enumConstructor, in: enumBody).first)
            try #require(enumStore.index < enumCall.index)
            try #require(enumCall.arguments.count == 1 && enumCall.arguments.first == enumStore.arguments.first)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func unmarkedNestedClassKeepsStaticConstruction(indexed: Bool, instanceReceiver: Bool) throws {
        let producer = try producerRecords()
        let nested = try #require(producer.records.first { $0.fqName == "importedinner.Outer.Nested" })
        try #require(!nested.isInnerClass)
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        defer { try? FileManager.default.removeItem(at: library) }
        try writeMetadata(producer.records, indexed: indexed, directory: library)
        let call = instanceReceiver ? "Outer().Nested()" : "Outer.Nested()"
        try withTemporaryFile(contents: "import importedinner.*\nfun main() { \(call) }") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [library.path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == instanceReceiver, "\(ctx.diagnostics.diagnostics)")
            if instanceReceiver { assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx) }
        }
    }
}
#endif
