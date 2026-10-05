#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibraryMetadataSignatureParsingTests {

    @Test func memberExtensionImportPreservesOwnerAndDefaultStubReceivers() throws {
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: libDir) }
        let manifest = """
        { "formatVersion": 1, "moduleName": "Receivers", "metadata": "metadata.bin" }
        """
        let metadata = """
        symbols=4
        class _ fq=receivers.Owner schema=v1
        class _ fq=receivers.Other schema=v1
        function _ fq=receivers.Owner.add schema=v1 arity=1 sig=F1<RI,I,I> memberExtension=1 default=1 defaultLink=owner_add_default link=owner_add
        function _ fq=receivers.Owner.other schema=v1 arity=0 sig=F0<RLreceivers.Other;,I> memberExtension=1 link=owner_other
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "Consumer", emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options, symbols: symbols, types: types,
                diagnostics: diagnostics, interner: interner,
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            #expect(!diagnostics.hasError)
            let owner = try #require(symbols.allSymbols().first { interner.resolve($0.name) == "Owner" })
            let add = try #require(symbols.allSymbols().first { interner.resolve($0.name) == "add" })
            let other = try #require(symbols.allSymbols().first { interner.resolve($0.name) == "other" })
            #expect(symbols.memberExtensionOwnerSymbol(for: add.id) == owner.id)
            #expect(symbols.memberExtensionOwnerSymbol(for: other.id) == owner.id)
            let stub = SyntheticSymbolScheme.defaultStubSymbol(for: add.id)
            let signature = try #require(symbols.functionSignature(for: stub))
            #expect(signature.receiverType == nil)
            #expect(signature.parameterTypes.count == 4)
            let dispatchType = try #require(signature.parameterTypes.first)
            if case let .classType(classType) = types.kind(of: dispatchType) {
                #expect(classType.classSymbol == owner.id)
            } else {
                Issue.record("Expected the dispatch receiver before the extension receiver")
            }
            #expect(signature.parameterTypes.dropFirst().allSatisfy { $0 == types.intType })
            #expect(symbols.externalLinkName(for: stub) == "owner_add_default")
        }
    }

    @Test(arguments: [false, true])
    func importedInlineParameterReturnPermissionsSurviveNormalization(indexed: Bool) throws {
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: libDir) }

        let manifest = """
        {"formatVersion": 1, "moduleName": "InlinePermissions", "metadata": "metadata.bin"}
        """
        let record = MetadataRecord(
            kind: .function,
            mangledName: "_kk_inline_permissions",
            fqName: "permissions.apply",
            arity: 3,
            isSuspend: false,
            isInline: true,
            typeSignature: "F3<F0<I>,F0<I>,F0<I>,I>",
            valueParameterAllowsNonLocalReturn: [false, false, true]
        )
        let encoder = MetadataEncoder()
        let metadata = indexed ? encoder.serializeIndexed([record]) : encoder.serialize([record])
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump, searchPaths: [libDir.path])
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let phase = DataFlowSemaPhase()
            let work = phase.loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: ImportedInlineFunctionStore()
            )
            let symbol = try #require(symbols.lookup(fqName: ["permissions", "apply"].map(interner.intern)))
            #expect(symbols.functionSignature(for: symbol)?.valueParameterAllowsNonLocalReturn == [false, false, true])
            phase.normalizeImportedLibraryMemberSignatures(
                work, symbols: symbols, types: types, diagnostics: diagnostics, interner: interner
            )
            #expect(symbols.functionSignature(for: symbol)?.valueParameterAllowsNonLocalReturn == [false, false, true])
            #expect(!diagnostics.hasError)
        }
    }

    @Test func testDeeplyNestedNullableSignatureDoesNotCrashAndEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let nesting = 1000
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "DeepNest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nproperty _ fq=deepnest.x schema=v1 sig=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DeepNestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let inlineFns = ImportedInlineFunctionStore()

            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.count == 1, "Expected a single malformed-signature warning for recursion depth, got: \(diagnostics.diagnostics.map(\.code))")
            let xSymbol = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "x" && symbol.kind == .property
            }
            #expect(xSymbol != nil, "Property symbol should still be imported despite the malformed signature")
        }
    }

    @Test func testDeeplyNestedValueClassUnderlyingSignatureDoesNotCrashAndEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let nesting = 1000
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ValueClassDeepNest",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nclass _ fq=vc.deep schema=v1 valueClass=1 valueUnderlying=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ValueClassDeepNestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let inlineFns = ImportedInlineFunctionStore()

            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.count == 1, "Expected a single malformed-signature warning for value class underlying recursion depth, got: \(diagnostics.diagnostics.map(\.code))")
        }
    }

    @Test func testSignatureAtDepthLimitParsesWithoutWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // The leaf adds one parser call, so 63 wrappers exercise the 64-call limit.
        let nesting = 63
        let prefix = String(repeating: "Q<", count: nesting)
        let suffix = String(repeating: ">", count: nesting)
        let sig = prefix + "I" + suffix

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "AtDepthLimit",
          "metadata": "metadata.bin"
        }
        """
        let metadata = "symbols=1\nproperty _ fq=atdepth.x schema=v1 sig=\(sig)\n"
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "AtDepthLimitApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let inlineFns = ImportedInlineFunctionStore()

            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.isEmpty, "Expected a 63-deep nullable signature to parse within the depth limit: \(diagnostics.diagnostics.map(\.code))")
            let xSymbol = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "x" && symbol.kind == .property
            }
            #expect(xSymbol != nil, "Property 'x' should be imported")
        }
    }

    @Test func testByteAndShortSignaturesParseWithoutWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "ByteShortSig",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=2
        property _ fq=byte.x schema=v1 sig=B
        property _ fq=short.y schema=v1 sig=S
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ByteShortSigApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            let interner = StringInterner()
            let inlineFns = ImportedInlineFunctionStore()

            _ = DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: interner,
                importedInlineFunctions: inlineFns
            )

            let warnings = diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LIB-0003" }
            #expect(warnings.isEmpty, "Expected Byte/Short signatures to parse without malformed-signature warnings: \(diagnostics.diagnostics.map(\.code))")

            let byteX = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "x" && symbol.kind == .property
            }
            let shortY = symbols.allSymbols().first { symbol in
                interner.resolve(symbol.name) == "y" && symbol.kind == .property
            }
            #expect(byteX != nil, "Property 'x' should be imported")
            #expect(shortY != nil, "Property 'y' should be imported")
            #expect(byteX.map({ symbols.propertyType(for: $0.id) }) == types.byteType, "Byte signature should resolve to byteType")
            #expect(shortY.map({ symbols.propertyType(for: $0.id) }) == types.shortType, "Short signature should resolve to shortType")
        }
    }
}
#endif
