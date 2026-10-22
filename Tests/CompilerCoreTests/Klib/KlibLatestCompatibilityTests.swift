@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing

@Suite
struct KlibLatestCompatibilityTests {
    private var fixturePath: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Kotlin2_4_21/basics.klib").path
    }

    @Test
    func readsLatestNativeManifestAndMultipleFiles() throws {
        let container = try KlibContainer(path: fixturePath)
        let manifest = try container.manifest()
        #expect(manifest.compilerVersion == KlibManifest.Version("2.4.21"))
        #expect(manifest.abiVersion == KlibManifest.Version("2.4.0"))
        #expect(manifest.builtinsPlatform == "NATIVE")
        #expect(manifest.compatibility == .supported)
        let module = try KlibIrModule(container: container)
        #expect(module.fileCount == 3)
        let dump = try KlibIrDump.dump(module)
        for name in ["add", "defaults", "Counter", "acrossFile", "identity"] {
            #expect(dump.contains(name))
        }
        for index in 0 ..< module.fileCount {
            let file = try module.file(index)
            #expect(try module.fqName(file.fqName, fileIndex: index) == "kliblatest")
            for declaration in try module.declarations(fileIndex: index) {
                if case .function(let function) = declaration, let body = function.base.bodyIndex {
                    _ = try module.body(body, fileIndex: index)
                    _ = try module.signature(function.base.base.symbol.signatureIndex, fileIndex: index)
                }
            }
        }
    }

    @Test
    func readsModernOmittedArgumentsAndDependentDefaults() throws {
        let module = try KlibIrModule(container: KlibContainer(path: fixturePath))
        var sawDefaults = false
        var sawMissingArgument = false
        for fileIndex in 0 ..< module.fileCount {
            for case .function(let function) in try module.declarations(fileIndex: fileIndex) {
                let name = try module.string(function.base.nameType.nameIndex, fileIndex: fileIndex)
                if name == "defaults" {
                    #expect(function.base.regularParameters.count == 2)
                    for parameter in function.base.regularParameters {
                        let index = try #require(parameter.defaultValueIndex)
                        _ = try module.expressionBody(index, fileIndex: fileIndex)
                    }
                    sawDefaults = true
                }
                if name == "callDefaults" {
                    let body = try module.body(#require(function.base.bodyIndex), fileIndex: fileIndex)
                    guard case .blockBody(let statements) = body.kind,
                          case .expression(let expression) = statements.first?.kind,
                          case .return(_, let value) = expression.kind,
                          case .call(_, let access, _, _) = value.kind,
                          case .missingExpression = access.arguments.first?.kind else {
                        Issue.record("expected a modern call with an omitted first argument")
                        continue
                    }
                    #expect(access.arguments.count == 2)
                    #expect(access.regularArguments.isEmpty)
                    sawMissingArgument = true
                }
            }
        }
        #expect(sawDefaults)
        #expect(sawMissingArgument)
    }

    @Test
    func importsVisibilityModalityAndVarargElementTypes() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let phase = DataFlowSemaPhase()
        let loaded = try #require(phase.loadKlibModule(path: fixturePath, diagnostics: diagnostics))
        let records = phase.materializeKlibRecords(module: loaded, interner: interner, diagnostics: diagnostics).records
        func record(_ name: String) throws -> DataFlowSemaPhase.ImportedLibrarySymbolRecord {
            try #require(records.first { $0.fqName.map { interner.resolve($0) }.joined(separator: ".") == name })
        }
        #expect(try record("kliblatest.hidden").visibility == .private)
        #expect(try record("kliblatest.internalHelper").visibility == .internal)
        #expect(try record("kliblatest.Base.number").modality == .open)
        #expect(try record("kliblatest.count").typeSignature == "F1<I,I>")
        #expect(try record("kliblatest.count").valueParameterIsVararg == [true])
        #expect(diagnostics.diagnostics.isEmpty)
    }

    @Test
    func restoresInheritedDefaultsAfterBindingImportedSignatures() throws {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let diagnostics = DiagnosticEngine()
        let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: CompilerOptions(
                moduleName: "KlibDefaultsImport", inputs: [], outputPath: "/tmp/unused-klib-import",
                emit: .kirDump, searchPaths: [fixturePath], target: defaultTargetTriple()
            ),
            symbols: symbols, types: TypeSystem(), diagnostics: diagnostics,
            interner: interner, importedInlineFunctions: ImportedInlineFunctionStore()
        )
        #expect(work.klibModules.count == 1)
        let base = try #require(symbols.lookupAll(fqName: ["kliblatest", "Base", "number"].map { interner.intern($0) }).first)
        let derived = try #require(symbols.lookupAll(fqName: ["kliblatest", "Derived", "number"].map { interner.intern($0) }).first)
        #expect(symbols.functionSignature(for: derived)?.valueParameterHasDefaultValues == [true])
        #expect(symbols.overrideDefaultsBaseSymbol(for: derived) == base)
        #expect(!diagnostics.hasError)
    }

    @Test
    func readsLosslessStringLiteralsFromLatestNativeCompiler() throws {
        let module = try KlibIrModule(container: KlibContainer(path: fixturePath))
        let expected: [String: [UInt16]] = [
            "highSurrogate": [0xD800], "lowSurrogate": [0xDC00],
            "markers": [0xE800, 0xE000], "supplementary": [0xD83D, 0xDE00],
            "embeddedNull": [0x41, 0, 0x42],
        ]
        var observed = Set<String>()
        for fileIndex in 0 ..< module.fileCount {
            for case .function(let function) in try module.declarations(fileIndex: fileIndex) {
                let name = try module.string(function.base.nameType.nameIndex, fileIndex: fileIndex)
                guard let units = expected[name] else { continue }
                let body = try module.body(#require(function.base.bodyIndex), fileIndex: fileIndex)
                guard case .blockBody(let statements) = body.kind,
                      case .expression(let expression) = statements.first?.kind,
                      case .return(_, let value) = expression.kind,
                      case .constString(let index) = value.kind else {
                    Issue.record("expected a returned string literal for \(name)")
                    continue
                }
                let literal = try module.stringLiteral(index, fileIndex: fileIndex)
                #expect(KotlinStringSurrogateEncoding.utf16CodeUnits(literal) == units)
                observed.insert(name)
            }
        }
        #expect(observed == Set(expected.keys))
    }

    @Test
    func readsUnpackedLatestKlibAndRejectsInconsistentTableRows() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).klib")
        defer { try? fm.removeItem(at: root) }
        let packed = try KlibContainer(path: fixturePath)
        let component = root.appendingPathComponent("default")
        for entry in packed.entryPaths() {
            let path = component.appendingPathComponent(entry)
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(packed.read(entry)).write(to: path)
        }
        let unpacked = try KlibIrModule(container: KlibContainer(path: root.path))
        #expect(try KlibIrDump.dump(unpacked) == KlibIrDump.dump(KlibIrModule(container: packed)))
        try Data([0, 0, 0, 0]).write(to: component.appendingPathComponent("ir/types.knt"))
        #expect(throws: KlibFormatError.self) {
            _ = try KlibIrModule(container: KlibContainer(path: root.path))
        }
    }
}
