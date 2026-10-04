@testable import CompilerCore
import Foundation
import Testing

/// Declaration materialization: real Kotlin/Native `.klib` IR declarations
/// become `ImportedLibrarySymbolRecord`s and register in `SymbolTable`/
/// `TypeSystem` through the same pipeline as `.kklib` metadata.
@Suite
struct KlibDeclImportTests {
    private static var fixturePath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/demo.klib")
            .path
    }

    private struct ImportedFixture {
        let symbols: SymbolTable
        let types: TypeSystem
        let interner: StringInterner
        let diagnostics: DiagnosticEngine
        let work: DataFlowSemaPhase.LibraryImportDeferredWork
    }

    /// Runs the real `loadImportedLibrarySymbols` path with the fixture klib
    /// as the only `-I` library.
    private static func importFixture() throws -> ImportedFixture? {
        guard FileManager.default.fileExists(atPath: fixturePath) else { return nil }
        let fm = FileManager.default
        let searchDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: searchDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: searchDir) }
        try fm.copyItem(
            atPath: fixturePath,
            toPath: searchDir.appendingPathComponent("demo.klib").path
        )
        let sourcePath = searchDir.appendingPathComponent("main.kt").path
        try "fun main() = 0".write(toFile: sourcePath, atomically: true, encoding: .utf8)

        let ctx = makeCompilationContext(
            inputs: [sourcePath],
            moduleName: "KlibDeclApp",
            emit: .kirDump,
            searchPaths: [searchDir.path]
        )
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let symbols = SymbolTable()
        let types = TypeSystem()
        let work = DataFlowSemaPhase().loadImportedLibrarySymbols(
            options: ctx.options,
            symbols: symbols,
            types: types,
            diagnostics: diagnostics,
            interner: interner,
            importedInlineFunctions: ImportedInlineFunctionStore()
        )
        return ImportedFixture(
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics,
            work: work
        )
    }

    private func fqName(_ interner: StringInterner, _ dotted: String) -> [InternedString] {
        dotted.split(separator: ".").map { interner.intern(String($0)) }
    }

    @Test
    func registersTopLevelAndMemberSymbols() throws {
        guard let fixture = try Self.importFixture() else { return }
        let interner = fixture.interner

        let add = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.add"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(add.count == 1)
        #expect(add.first?.kind == .function)
        #expect(add.first?.flags.contains(.importedLibrary) == true)

        let greeter = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(greeter.first?.kind == .class)

        let ctor = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.<init>"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(ctor.first?.kind == .constructor)

        let name = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.name"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(name.contains { $0.kind == .property })

        let backing = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.$backing_name"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(backing.first?.kind == .backingField)

        let greet = fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.greet"))
            .compactMap { fixture.symbols.symbol($0) }
        #expect(greet.first?.kind == .function)

        // Package symbols are synthesized from record fq names.
        let demoPackage = fixture.symbols.lookupAll(fqName: [interner.intern("demo")])
            .compactMap { fixture.symbols.symbol($0) }
        #expect(demoPackage.contains { $0.kind == .package })

        #expect(!fixture.diagnostics.hasError,
                "unexpected errors: \(fixture.diagnostics.diagnostics.map(\.code))")
    }

    @Test
    func decodesFunctionSignatures() throws {
        guard let fixture = try Self.importFixture() else { return }
        let interner = fixture.interner

        let addID = try #require(
            fixture.symbols.lookupAll(fqName: fqName(interner, "demo.add")).first
        )
        let addSignature = try #require(fixture.symbols.functionSignature(for: addID))
        #expect(addSignature.parameterTypes.count == 2)
        for parameterType in addSignature.parameterTypes {
            guard case .primitive(let primitive, _) = fixture.types.kind(of: parameterType) else {
                Issue.record("expected Int parameter, got \(fixture.types.kind(of: parameterType))")
                return
            }
            #expect(primitive == .int)
        }
        guard case .primitive(let returnPrimitive, _) = fixture.types.kind(of: addSignature.returnType)
        else {
            Issue.record("expected Int return")
            return
        }
        #expect(returnPrimitive == .int)

        // `greet` is a member: the signature carries the dispatch receiver as
        // `RLdemo.Greeter;` and returns `String`.
        let greetID = try #require(
            fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.greet")).first
        )
        let greetSignature = try #require(fixture.symbols.functionSignature(for: greetID))
        #expect(greetSignature.parameterTypes.isEmpty)
        #expect(greetSignature.receiverType != nil)
        #expect(fixture.types.kind(of: greetSignature.returnType) == fixture.types.kind(of: fixture.types.stringType))
    }

    @Test
    func decodesPropertyTypes() throws {
        guard let fixture = try Self.importFixture() else { return }
        let interner = fixture.interner

        let nameID = try #require(
            fixture.symbols.lookupAll(fqName: fqName(interner, "demo.Greeter.name"))
                .first(where: { fixture.symbols.symbol($0)?.kind == .property })
        )
        let propertyType = try #require(fixture.symbols.propertyType(for: nameID))
        #expect(fixture.types.kind(of: propertyType) == fixture.types.kind(of: fixture.types.stringType))
    }

    @Test
    func registersModuleFQName() throws {
        guard let fixture = try Self.importFixture() else { return }
        let interner = fixture.interner
        let addID = try #require(
            fixture.symbols.lookupAll(fqName: fqName(interner, "demo.add")).first
        )
        let moduleFQN = fixture.symbols.moduleFQN(for: addID)
        #expect(moduleFQN.map { interner.resolve($0) } == "demo2")
    }
}
