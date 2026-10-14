#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CompactMetadataIndexTests {
    @Test(arguments: CompactMetadataIndex.kinds, CompactMetadataIndex.visibilities)
    func compactShellAndBodyMatchV2(kind: SymbolKind, visibility: Visibility) throws {
        let record = MetadataRecord(
            kind: kind, visibility: visibility, mangledName: "_KK_日本語", fqName: "demo.日本語",
            arity: 3, isSuspend: true, isInline: true, isOperator: true, isInfix: true,
            isOverride: true, isMemberExtension: true, receiverOwnerFQName: "demo.Owner",
            typeSignature: "F3<I,I,I,I>", valueParameterNames: ["a", "b", "c"],
            defaultStubExternalLinkName: "default_call", externalLinkName: "external_call",
            declaredFieldCount: 1, companionObjectFQName: "demo.Owner.Companion",
            objectInitializerLinkName: "object_init", companionInitializerLinkName: "companion_init",
            enumStaticInitLinkName: "enum_init", isDataClass: true, isOpenClass: true,
            isInnerClass: true, modality: .abstract, isSealedClass: true, isFunInterface: true,
            annotations: [MetadataAnnotationRecord(annotationFQName: "demo.Mark", arguments: ["日本語"])],
            isValueClass: true, isExpect: true, isActual: true,
            propertyReceiverTypeSignature: "Ldemo.Owner;", propertyGetterExternalLinkName: "getter",
            propertySetterExternalLinkName: "setter", propertySetterVisibility: .private, isMutable: true,
            nominalTypeParametersSignature: "Ldemo.Owner<O<T1>>;"
        )
        let encoder = MetadataEncoder()
        let v2 = try #require(IndexedMetadataFile(data: Data(encoder.serializeIndexed([record]).utf8)))
        let data = encoder.serializeCompactIndexed([record])
        let v3 = try #require(IndexedMetadataFile(data: data))
        let entry = try #require(v3.entries.first)
        #expect(entry.compactRecord != nil)
        #expect(encoder.serialize([entry.record]) == encoder.serialize([v2.entries[0].record]))
        #expect(entry.hasCompleteInitializerInfo == v2.entries[0].hasCompleteInitializerInfo)
        #expect(entry.record.typeSignature == nil)
        #expect(entry.record.annotations.isEmpty)
        #expect(encoder.serialize([try #require(v3.record(for: entry))]) == encoder.serialize([record]))
        #expect(encoder.serialize(MetadataDecoder().decode(data)) == encoder.serialize([record]))
        #expect(data == encoder.serializeCompactIndexed([record]))
    }

    @Test(arguments: CompactMetadataIndex.visibilities)
    func setterVisibilityIsAvailableBeforeBodyDecode(visibility: Visibility) throws {
        let record = MetadataRecord(
            kind: .property, mangledName: "_value", fqName: "demo.value",
            typeSignature: "I", propertySetterVisibility: visibility, isMutable: true
        )
        let file = try #require(IndexedMetadataFile(data: MetadataEncoder().serializeCompactIndexed([record])))
        let indexRecord = try #require(file.entries[0].compactRecord)
        #expect(indexRecord.propertySetterVisibility == visibility)
        #expect(indexRecord.record.propertySetterVisibility == visibility)
        let shell = try #require(DataFlowSemaPhase().makeImportedLibraryIndexRecord(
            indexRecord, path: "test", diagnostics: DiagnosticEngine(),
            interner: StringInterner(), nominalTypeParametersByFQName: [:]
        ))
        #expect(shell.propertySetterVisibility == visibility)
        #expect(shell.typeSignature == nil)
    }

    @Test func innerClassFlagSurvivesEveryMetadataLayout() throws {
        let record = MetadataRecord(
            kind: .class, mangledName: "_inner", fqName: "demo.Outer.Inner", isInnerClass: true
        )
        let encoder = MetadataEncoder()
        for data in [Data(encoder.serialize([record]).utf8), Data(encoder.serializeIndexed([record]).utf8),
                     encoder.serializeCompactIndexed([record])] {
            let decoded = try #require(MetadataDecoder().decode(data).first)
            #expect(decoded.isInnerClass)
        }
    }

    @Test(arguments: [MetadataModality.final, .open, .abstract])
    func modalityAndMinimalDefaultsRoundTrip(modality: MetadataModality) throws {
        let record = MetadataRecord(kind: .class, fqName: "demo.C", modality: modality)
        let file = try #require(IndexedMetadataFile(data: MetadataEncoder().serializeCompactIndexed([record])))
        #expect(file.entries[0].record.modality == modality)
        #expect(file.entries[0].record.externalLinkName == nil)
        #expect(file.entries[0].record.visibility == .public)
        #expect(file.entries[0].record.arity == 0)
        #expect(file.entries[0].hasCompleteInitializerInfo)
    }

    @Test func emptyAndSlicedDataAreReadable() throws {
        let encoder = MetadataEncoder()
        #expect(try #require(IndexedMetadataFile(data: encoder.serializeCompactIndexed([]))).entries.isEmpty)
        let records = [MetadataRecord(kind: .property, fqName: "demo.日本語", typeSignature: "I")]
        var data = Data("padding".utf8)
        data.append(encoder.serializeCompactIndexed(records))
        let file = try #require(IndexedMetadataFile(data: data.dropFirst(7)))
        #expect(file.entries[0].fqName == "demo.日本語")
        #expect(try #require(file.record(for: file.entries[0])).typeSignature == "I")
    }

    @Test func unusedInvalidBodyRemainsLazy() throws {
        let records = [
            MetadataRecord(kind: .property, fqName: "demo.used", typeSignature: "I"),
            MetadataRecord(kind: .class, fqName: "demo.Unused"),
        ]
        var data = MetadataEncoder().serializeCompactIndexed(records)
        data[data.count - 2] = 0xFF
        let file = try #require(IndexedMetadataFile(data: data))
        #expect(try #require(file.record(for: file.entries[0])).typeSignature == "I")
        #expect(file.record(for: file.entries[1]) == nil)
        #expect(try #require(file.record(for: file.entries[0])).fqName == "demo.used")
    }

    @Test func rejectsTruncationAndMalformedTables() throws {
        let data = MetadataEncoder().serializeCompactIndexed([
            MetadataRecord(kind: .function, mangledName: "_call", fqName: "demo.call", arity: 1)
        ])
        let header = CompactMetadataIndex.magic.count
        let stringBytes = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: header + 8, as: UInt32.self))) }
        let table = header + 16 + stringBytes
        // Every truncated header/string/table/body must reject without large
        // allocations, integer overflow, unaligned traps or body decoding.
        for end in 0 ..< data.count {
            #expect(IndexedMetadataFile(data: data.prefix(end)) == nil)
        }
        for (offset, value) in [
            (header, UInt32.max), (header + 4, UInt32.max), (header + 8, UInt32.max),
            (header + 12, UInt32(79)), (header + 16, UInt32.max),
            (table + 20, UInt32(1 << 21)), (table + 20, UInt32(5 << 18)), (table + 20, UInt32(3 << 16)),
            (table + 24, UInt32(16)), (table + 28, UInt32(4)),
            (table + 32, UInt32.max), (table + 32, UInt32(0)),
        ] {
            var corrupt = data
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { corrupt.replaceSubrange(offset ..< offset + 4, with: $0) }
            #expect(IndexedMetadataFile(data: corrupt) == nil)
        }
        for offset in [table, table + 8] {
            var corrupt = data
            corrupt.replaceSubrange(offset ..< offset + 8, with: repeatElement(UInt8(0xFF), count: 8))
            #expect(IndexedMetadataFile(data: corrupt) == nil)
        }
        var invalidUTF8 = data
        invalidUTF8[header + 16 + 8] = 0xFF
        #expect(IndexedMetadataFile(data: invalidUTF8) == nil)
    }

    @Test func compactShellDoesNotReadSignaturesOrAllocateBodyRecords() throws {
        let record = MetadataRecord(
            kind: .function, mangledName: "_call", fqName: "demo.call", arity: 1, isInline: true,
            receiverOwnerFQName: "demo.Owner", typeSignature: "F1<I,I>",
            externalLinkName: "_call", isExpect: true
        )
        let file = try #require(IndexedMetadataFile(data: MetadataEncoder().serializeCompactIndexed([record])))
        let indexRecord = try #require(file.entries[0].compactRecord)
        let shell = try #require(DataFlowSemaPhase().makeImportedLibraryIndexRecord(
            indexRecord, path: "test", diagnostics: DiagnosticEngine(),
            interner: StringInterner(), nominalTypeParametersByFQName: [:]
        ))
        #expect(shell.typeSignature == nil)
        #expect(shell.annotations.isEmpty)
        #expect(shell.isInline && shell.isExpect)
        #expect(shell.externalLinkName == "_call")
        #expect(shell.receiverOwnerFQName?.count == 2)
        #expect(MetadataEncoder.compactInlineKIRMangledNames(in: MetadataEncoder().serializeCompactIndexed([record])) == ["_call"])
    }
    @Test(arguments: ["duplicate", "arity", "malformed", "magic", "v1", "v2"])
    func invalidCompactImportsReportDiagnostics(problem: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = problem == "arity"
            ? [MetadataRecord(kind: .function, mangledName: "_call", fqName: "demo.call", arity: 1025)]
            : Array(repeating: MetadataRecord(
                kind: .class, mangledName: "_box", fqName: "demo.Box", nominalTypeParametersSignature: "C0"
            ), count: problem == "duplicate" ? 2 : 1)
        var data = MetadataEncoder().serializeCompactIndexed(records)
        if problem == "malformed" {
            data.removeLast()
        } else if problem == "magic" {
            data[0] = 0
        } else if problem == "v1" {
            data = Data(MetadataEncoder().serialize(records).utf8)
        } else if problem == "v2" {
            data = Data(MetadataEncoder().serializeIndexed(records).utf8)
        }
        try data.write(to: directory.appendingPathComponent("metadata.bin"))
        try "{\"formatVersion\":2,\"moduleName\":\"InvalidCompact\",\"metadata\":\"metadata.bin\"}"
            .write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let context = makeCompilationContext(inputs: [], searchPaths: [directory.path], includeStdlib: false)
        let diagnostics = DiagnosticEngine()
        let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: context.options, symbols: SymbolTable(), types: TypeSystem(),
            diagnostics: diagnostics, interner: context.interner,
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LIB-0024" })
        #expect(work.importedBindings.isEmpty)
    }

}
#endif
