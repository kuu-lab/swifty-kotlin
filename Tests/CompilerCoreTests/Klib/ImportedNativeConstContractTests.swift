@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ImportedNativeConstContractTests {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ImportedConstants.klib")
    }

    private func consumer(_ source: String) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path], searchPaths: [fixture.path], includeStdlib: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test
    func nativeIRFlagsDistinguishConstFromLiteralInitializedVal() throws {
        // This fixture is produced by Kotlin/Native, including its property
        // flags and literal backing-field expressions, rather than hand records.
        let phase = DataFlowSemaPhase()
        let diagnostics = DiagnosticEngine()
        let module = try #require(phase.loadKlibModule(path: fixture.path, diagnostics: diagnostics))
        let interner = StringInterner()
        let materialized = phase.materializeKlibRecords(
            module: module, interner: interner, diagnostics: diagnostics
        )
        let ir = try #require(materialized.ir)
        try #require(ir.fileCount == 1)
        let declarations = try ir.declarations(fileIndex: 0)
        var properties: [String: KlibProperty] = [:]
        for declaration in declarations {
            guard case let .property(property) = declaration else { continue }
            properties[try ir.string(property.nameIndex, fileIndex: 0)] = property
        }
        let nonConst: Set<String> = ["ordinary", "mutableValue", "ordinaryBoolean"]
        let constants: Set<String> = ["SIZE", "ENABLED", "SMALL", "WORD", "BIG", "LETTER", "FRACTION", "RATIO", "MESSAGE", "MASK", "WIDE", "BYTE_MASK", "SHORT_MASK"]
        try #require(Set(properties.keys) == constants.union(nonConst))
        for name in constants.union(nonConst) {
            let property = try #require(properties[name])
            try #require(property.backingField?.initializerIndex != nil)
            try #require(property.base.flags.isConst == constants.contains(name))
            let initializer = try #require(property.backingField?.initializerIndex)
            let expression = try ir.expressionBody(initializer, fileIndex: 0)
            if name == "SIZE" {
                guard case .constInt(8192) = expression.kind else {
                    Issue.record("Native SIZE initializer is not an Int constant")
                    return
                }
            } else if name == "ENABLED" {
                guard case .constBool(true) = expression.kind else {
                    Issue.record("Native ENABLED initializer is not a Boolean constant")
                    return
                }
            } else if name == "FRACTION" {
                guard case .constFloat(let bits) = expression.kind else {
                    Issue.record("Native FRACTION initializer is not a Float constant")
                    return
                }
                try #require(Float(bitPattern: bits) == 1.5)
            }
        }
        let records = materialized.records.filter { $0.kind == .property }
        func record(_ name: String) throws -> DataFlowSemaPhase.ImportedLibrarySymbolRecord {
            try #require(records.first {
                $0.fqName.map(interner.resolve).joined(separator: ".") == "nativeconstantproducer." + name
            })
        }
        try #require(try record("SIZE").constValueLiteral == "i:8192")
        try #require(try record("ENABLED").constValueLiteral == "b:1")
        let encoded: [String: String] = [
            "SMALL": "i:7", "WORD": "i:300", "BIG": "l:1234567890123", "LETTER": "c:90",
            "FRACTION": "f:\(Double(1.5).bitPattern)", "RATIO": "d:\(Double(2.5).bitPattern)",
            "MESSAGE": "s:aGVsbG8=", "MASK": "u:4294967295", "WIDE": "ul:18446744073709551615",
            "BYTE_MASK": "u:255", "SHORT_MASK": "u:65535"
        ]
        for (name, expected) in encoded {
            let importedRecord = try record(name)
            try #require(importedRecord.constValueLiteral == expected)
        }
        for name in ["ordinary", "mutableValue", "ordinaryBoolean"] {
            try #require(try record(name).constValueLiteral == nil)
        }
        try #require(!diagnostics.hasError, "\(diagnostics.diagnostics)")

        let ctx = try consumer("""
        package nativeconstantconsumer
        import nativeconstantproducer.*
        const val COPIED = SIZE
        const val SWITCH = ENABLED
        const val COPIED_SMALL: Byte = SMALL
        const val COPIED_WORD: Short = WORD
        const val COPIED_BIG: Long = BIG
        const val COPIED_LETTER: Char = LETTER
        const val COPIED_FRACTION: Float = FRACTION
        const val COPIED_RATIO: Double = RATIO
        const val COPIED_MESSAGE: String = MESSAGE
        const val COPIED_MASK: UInt = MASK
        const val COPIED_WIDE: ULong = WIDE
        const val COPIED_BYTE_MASK: UByte = BYTE_MASK
        const val COPIED_SHORT_MASK: UShort = SHORT_MASK
        fun ordinaryValue(): Int = ordinary
        fun ordinarySwitch(): Boolean = ordinaryBoolean
        """)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let copied = try #require(sema.symbols.lookup(
            fqName: ["nativeconstantconsumer", "COPIED"].map(ctx.interner.intern)
        ))
        let enabled = try #require(sema.symbols.lookup(
            fqName: ["nativeconstantconsumer", "SWITCH"].map(ctx.interner.intern)
        ))
        try #require(sema.symbols.constValueExprKind(for: copied) == .intLiteral(8192))
        try #require(sema.symbols.constValueExprKind(for: enabled) == .boolLiteral(true))
        for (name, expected) in encoded {
            let copiedScalar = try #require(sema.symbols.lookup(
                fqName: ["nativeconstantconsumer", "COPIED_" + name].map(ctx.interner.intern)
            ))
            let value = try #require(sema.symbols.constValueExprKind(for: copiedScalar))
            let actual = MetadataConstValueCoder.encode(value, resolver: ctx.interner.resolve)
            try #require(actual == expected)
        }
        for name in ["ordinary", "mutableValue", "ordinaryBoolean"] {
            let imported = try #require(sema.symbols.lookup(
                fqName: ["nativeconstantproducer", name].map(ctx.interner.intern)
            ))
            try #require(sema.symbols.symbol(imported)?.flags.contains(.constValue) == false)
            try #require(sema.symbols.constValueExprKind(for: imported) == nil)
        }
    }

    @Test(arguments: ["ordinary", "mutableValue", "ordinaryBoolean"])
    func nativeNonConstPropertiesCannotInitializeConsumerConst(name: String) throws {
        let ctx = try consumer("""
        package invalidnativeconstantconsumer
        import nativeconstantproducer.*
        const val INVALID = \(name)
        """)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.count == 1, "\(errors)")
        try #require(errors.first?.code == "KSWIFTK-SEMA-0083")
        let sema = try #require(ctx.sema)
        let invalid = try #require(sema.symbols.lookup(
            fqName: ["invalidnativeconstantconsumer", "INVALID"].map(ctx.interner.intern)
        ))
        try #require(sema.symbols.constValueExprKind(for: invalid) == nil)
    }
}
