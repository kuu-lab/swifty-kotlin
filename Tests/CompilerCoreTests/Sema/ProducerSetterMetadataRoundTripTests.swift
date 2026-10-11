// Scratch proposal only. Not type-checked or executed.
#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ProducerSetterMetadataRoundTripTests {
    // Use the actual producer layout and MetadataEncoder, not fabricated
    // public-property-key metadata. Both wire encodings must import it.
    @Test(arguments: [false, true], [false, true])
    func actualProducerStorageSurvivesExportAndConsumerWrites(
        includeNonPublic: Bool, indexed: Bool
    ) throws {
        let producer = makeContextFromSource("""
        package fixture
        open class Base {
            var inherited: Int = 1
                set(v) { field = v * 2 }
            private var baseHidden: Int = 0
                set(v) { field = v }
        }
        class Box : Base() {
            var value: Int = 0
                set(v) { field = v * 2 }
            var optional: Int? = null
                set(v) { field = v }
            var plain: Int = 0
            val computed: Int get() = 42
            val storedGetter: Int = 2
                get() = field + 1
            internal var internalValue: Int = 1
                set(v) { field = v }
            private var hidden: Int = 1
                set(v) { field = v }
        }
        """, moduleName: "SetterProducer")
        try runToKIR(producer)
        #expect(!producer.diagnostics.hasError, "\(producer.diagnostics.diagnostics)")
        let producerSema = try #require(producer.sema)
        let producerModule = try #require(producer.kir)
        let emittedFunctions = Set(producerModule.arena.declarations.compactMap { declaration -> SymbolID? in
            if case let .function(function) = declaration { return function.symbol }
            return nil
        })
        var links: [SymbolID: String] = [:]
        for property in producerSema.symbols.allSymbols() where property.kind == .property {
            let fqName = property.fqName.map(producer.interner.resolve).joined(separator: ".")
            guard fqName.hasPrefix("fixture.") else { continue }
            let getter = producerSema.symbols.extensionPropertyGetterAccessor(for: property.id)
                ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: property.id)
            let setter = producerSema.symbols.extensionPropertySetterAccessor(for: property.id)
                ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: property.id)
            // Do not invent default getters: only functions emitted by the
            // real producer may have external links in this metadata-only test.
            if emittedFunctions.contains(getter) { links[getter] = fqName.replacingOccurrences(of: ".", with: "_") + "_get" }
            if emittedFunctions.contains(setter) { links[setter] = fqName.replacingOccurrences(of: ".", with: "_") + "_set" }
        }
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: producerSema.symbols, types: producerSema.types,
            moduleName: "SetterProducer", interner: producer.interner,
            functionLinkNames: links, includeNonPublic: includeNonPublic
        ).filter { $0.fqName.hasPrefix("fixture.") }

        for ownerName in ["Base", "Box"] {
            let owner = try #require(producerSema.symbols.lookup(
                fqName: ["fixture", ownerName].map(producer.interner.intern)
            ))
            let layout = try #require(producerSema.symbols.nominalLayout(for: owner))
            let record = try #require(records.first { $0.fqName == "fixture." + ownerName })
            let offsets = try decodeOffsets(record.fieldOffsets)
            #expect(record.declaredFieldCount == layout.instanceFieldCount)
            #expect(record.declaredInstanceSizeWords == layout.instanceSizeWords)
            #expect(offsets.count <= layout.instanceFieldCount)
            #expect(Set(offsets.values).count == offsets.count)
            #expect(!offsets.keys.contains { $0.contains(".$backing_") })
        }
        let producerValue = try #require(producerSema.symbols.lookup(
            fqName: ["fixture", "Box", "value"].map(producer.interner.intern)
        ))
        let producerValueField = try #require(producerSema.symbols.backingFieldSymbol(for: producerValue))
        let producerBox = try #require(producerSema.symbols.parentSymbol(for: producerValue))
        let producerBoxLayout = try #require(producerSema.symbols.nominalLayout(for: producerBox))
        let valueOffset = try #require(producerBoxLayout.fieldOffsets[producerValueField])
        #expect(producerBoxLayout.fieldOffsets[producerValue] == nil,
                "The real source layout must still use its backing-field key")
        let boxRecord = try #require(records.first { $0.fqName == "fixture.Box" })
        let boxOffsets = try decodeOffsets(boxRecord.fieldOffsets)
        #expect(boxOffsets["fixture.Box.value"] == valueOffset)
        #expect(boxOffsets["fixture.Base.inherited"] != nil)
        #expect(boxOffsets["fixture.Box.storedGetter"] != nil)
        #expect(boxOffsets["fixture.Box.computed"] == nil,
                "Computed getter-only properties must not acquire storage")
        let valueRecord = try #require(records.first { $0.fqName == "fixture.Box.value" })
        #expect(valueRecord.propertyGetterExternalLinkName == nil)
        #expect(valueRecord.propertySetterExternalLinkName == "fixture_Box_value_set")
        for (name, visibility) in [("hidden", Visibility.private), ("internalValue", Visibility.internal)] {
            let record = records.first { $0.fqName == "fixture.Box." + name }
            #expect((record != nil) == includeNonPublic)
            if includeNonPublic { #expect(record?.visibility == visibility) }
        }
        let backingSymbol = try #require(producerSema.symbols.symbol(producerValueField))
        let backingName = backingSymbol.fqName.map(producer.interner.resolve).joined(separator: ".")
        #expect(records.contains { $0.fqName == backingName } == includeNonPublic,
                "Private backing records retain the existing visibility policy")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = """
        {"formatVersion":1,"moduleName":"SetterProducer","metadata":"metadata.bin"}
        """
        try manifest.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let metadata = indexed ? encoder.serializeIndexed(records) : encoder.serialize(records)
        try metadata.write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let consumerSource = """
        fun fixture.Box.bare() { value += 1; value--; optional = null; inherited += 1; plain += 1 }
        fun fixture.Box.read(): Int = value
        fun fixture.Box.readOptional(): Int? = optional
        fun fixture.Box.computedRead(): Int = computed
        fun fixture.Box.storedGetterRead(): Int = storedGetter
        """
        try withTemporaryFile(contents: consumerSource) { path in
            let consumer = makeCompilationContext(
                inputs: [path], moduleName: "SetterConsumer", searchPaths: [directory.path]
            )
            try runToKIR(consumer)
            #expect(!consumer.diagnostics.hasError, "\(consumer.diagnostics.diagnostics)")
            let sema = try #require(consumer.sema)
            let module = try #require(consumer.kir)
            let body = try findKIRFunctionBody(named: "bare", in: module, interner: consumer.interner)
            for (ownerName, propertyName, expectedCalls) in [("Box", "value", 2), ("Box", "optional", 1), ("Base", "inherited", 1)] {
                let property = try #require(sema.symbols.lookup(
                    fqName: ["fixture", ownerName, propertyName].map(consumer.interner.intern)
                ))
                let setter = try #require(sema.symbols.extensionPropertySetterAccessor(for: property))
                let owner = try #require(sema.symbols.parentSymbol(for: property))
                let layout = try #require(sema.symbols.nominalLayout(for: owner))
                #expect(layout.fieldOffsets[property] != nil,
                        "The consumer must read stored properties by their exported property keys")
                #expect(countCalls(to: setter, in: body) == expectedCalls)
            }
            let importedPlain = try #require(sema.symbols.lookup(
                fqName: ["fixture", "Box", "plain"].map(consumer.interner.intern)
            ))
            #expect(sema.symbols.extensionPropertySetterAccessor(for: importedPlain) == nil)
            #expect(body.contains { instruction in
                if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                    return consumer.interner.resolve(callee) == "kk_array_set"
                }
                return false
            }, "The default stored var must retain direct storage writes")
            for ownerName in ["Base", "Box"] {
                let importedOwner = try #require(sema.symbols.lookup(
                    fqName: ["fixture", ownerName].map(consumer.interner.intern)
                ))
                let importedLayout = try #require(sema.symbols.nominalLayout(for: importedOwner))
                let sourceOwner = try #require(producerSema.symbols.lookup(
                    fqName: ["fixture", ownerName].map(producer.interner.intern)
                ))
                let sourceLayout = try #require(producerSema.symbols.nominalLayout(for: sourceOwner))
                #expect(importedLayout.instanceFieldCount == sourceLayout.instanceFieldCount)
                #expect(importedLayout.instanceSizeWords == sourceLayout.instanceSizeWords)
                #expect(Set(importedLayout.fieldOffsets.values).count == importedLayout.fieldOffsets.count)
            }
            for name in ["read", "readOptional"] {
                let readBody = try findKIRFunctionBody(named: name, in: module, interner: consumer.interner)
                #expect(readBody.contains { instruction in
                    if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                        return consumer.interner.resolve(callee) == "kk_array_get_inbounds"
                    }
                    return false
                })
            }
            for (propertyName, functionName) in [("computed", "computedRead"), ("storedGetter", "storedGetterRead")] {
                let property = try #require(sema.symbols.lookup(
                    fqName: ["fixture", "Box", propertyName].map(consumer.interner.intern)
                ))
                let getter = try #require(sema.symbols.extensionPropertyGetterAccessor(for: property))
                let readBody = try findKIRFunctionBody(named: functionName, in: module, interner: consumer.interner)
                #expect(countCalls(to: getter, in: readBody) == 1,
                        "A canonical storage key must not replace an existing custom getter")
            }
        }
        // Serialization must not mutate the producer's storage layout.
        #expect(producerSema.symbols.nominalLayout(for: producerBox)?.fieldOffsets[producerValueField] == valueOffset)
        #expect(producerSema.symbols.nominalLayout(for: producerBox)?.fieldOffsets[producerValue] == nil)
    }

    @Test func canonicalStorageKeysPreserveSelectionInheritanceAndOffsetZero() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        func define(_ name: String, kind: SymbolKind, owner: SymbolID?, visibility: Visibility) -> SymbolID {
            let prefix = owner.flatMap { symbols.symbol($0)?.fqName } ?? [interner.intern("fixture")]
            let id = symbols.define(kind: kind, name: interner.intern(name), fqName: prefix + [interner.intern(name)],
                                    declSite: nil, visibility: visibility, flags: [])
            if let owner { symbols.setParentSymbol(owner, for: id) }
            return id
        }
        let base = define("Base", kind: .class, owner: nil, visibility: .public)
        let box = define("Box", kind: .class, owner: nil, visibility: .public)
        let value = define("value", kind: .property, owner: base, visibility: .public)
        let valueField = define("$backing_value", kind: .backingField, owner: base, visibility: .private)
        symbols.setBackingFieldSymbol(valueField, for: value)
        let plain = define("plain", kind: .property, owner: box, visibility: .public)
        let hidden = define("hidden", kind: .property, owner: box, visibility: .private)
        let hiddenField = define("$backing_hidden", kind: .backingField, owner: box, visibility: .private)
        symbols.setBackingFieldSymbol(hiddenField, for: hidden)
        let internalValue = define("internalValue", kind: .property, owner: box, visibility: .internal)
        let internalField = define("$backing_internalValue", kind: .backingField, owner: box, visibility: .private)
        symbols.setBackingFieldSymbol(internalField, for: internalValue)
        let computed = define("computed", kind: .property, owner: box, visibility: .public)
        let raw = define("raw", kind: .field, owner: box, visibility: .public)
        let offsets = [valueField: 0, plain: 1, hiddenField: 2, internalField: 3, raw: 4]
        let encoder = MetadataEncoder()
        #expect(encoder.serializeFieldOffsets(offsets, symbols: symbols, interner: interner,
                                             includedSymbolIDs: [base, box, value, plain, computed, raw])
                == "fixture.Base.value@0,fixture.Box.plain@1,fixture.Box.raw@4")
        let all = Set(symbols.allSymbols().map(\.id))
        let expectedAll = "fixture.Base.value@0,fixture.Box.plain@1,fixture.Box.hidden@2,fixture.Box.internalValue@3,fixture.Box.raw@4"
        #expect(encoder.serializeFieldOffsets(offsets, symbols: symbols, interner: interner,
                                             includedSymbolIDs: all) == expectedAll)
        #expect(encoder.serializeFieldOffsets(offsets, symbols: symbols, interner: interner) == expectedAll)
        // A property excluded from the record set cannot become a layout key.
        #expect(encoder.serializeFieldOffsets([valueField: 0], symbols: symbols, interner: interner,
                                             includedSymbolIDs: [valueField]) == "fixture.Base.$backing_value@0")
        #expect(offsets[valueField] == 0)
        #expect(offsets[value] == nil)
    }

    private func decodeOffsets(_ text: String?) throws -> [String: Int] {
        var result: [String: Int] = [:]
        for component in (text ?? "").split(separator: ",") {
            let pair = component.split(separator: "@", maxSplits: 1)
            #expect(pair.count == 2)
            let key = String(try #require(pair.first))
            let rawValue = try #require(pair.last)
            let value = try #require(Int(String(rawValue)))
            #expect(result[key] == nil, "Metadata must contain only one entry per canonical field name")
            result[key] = value
        }
        return result
    }

    private func countCalls(to symbol: SymbolID, in body: [KIRInstruction]) -> Int {
        body.filter { instruction in
            if case let .call(target, _, _, _, _, _, _, _) = instruction { return target == symbol }
            return false
        }.count
    }
}
#endif
