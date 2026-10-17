#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOBufferAPIShapeTests {
    private let bufferFQName = "kotlinx.io.Buffer"
    private let constructorFQName = "kotlinx.io.Buffer.<init>"

    private func repositoryRoot() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        return root
    }

    private func namedTypePath(
        _ typeID: TypeRefID,
        ast: ASTModule,
        context: CompilationContext
    ) throws -> [String] {
        guard case let .named(path, arguments, nullable)? = ast.arena.typeRef(typeID) else {
            Issue.record("Expected a named non-null Buffer supertype")
            return []
        }
        #expect(arguments.isEmpty)
        #expect(!nullable)
        return path.map(context.interner.resolve)
    }

    private func productionSourceDeclaration() throws -> (ASTModule, CompilationContext, ClassDecl) {
        let path = repositoryRoot()
            .appendingPathComponent("Sources/CompilerCore/Stdlib/kotlinx/io/Buffer.kt")
            .path
        let context = makeCompilationContext(inputs: [path], includeStdlib: false)
        try LoadSourcesPhase().run(context)
        try LexPhase().run(context)
        try ParsePhase().run(context)
        try BuildASTPhase().run(context)
        try #require(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")

        let ast = try #require(context.ast)
        let classes = ast.arena.declarations().compactMap { declaration -> ClassDecl? in
            guard case let .classDecl(classDeclaration) = declaration,
                  context.interner.resolve(classDeclaration.name) == "Buffer"
            else { return nil }
            return classDeclaration
        }
        try #require(classes.count == 1, "Expected one production Buffer class")
        return (ast, context, try #require(classes.first))
    }

    private func libraryArtifactURL() throws -> URL {
        TestStdlibCache.shared.prepare()
        return URL(fileURLWithPath: try #require(CompilerOptions.defaultStdlibLibraryPath), isDirectory: true)
    }

    @Test
    func productionSourceDeclaresOnlyPublicSourceAndSinkWithoutExplicitConstructor() throws {
        let (ast, context, buffer) = try productionSourceDeclaration()
        let packageNames = ast.sortedFiles.map { $0.packageFQName.map(context.interner.resolve) }
        #expect(packageNames.contains(["kotlinx", "io"]))
        #expect(context.interner.resolve(buffer.name) == "Buffer")
        #expect(buffer.modifiers.contains(.public))
        #expect(!buffer.modifiers.contains(.open))
        #expect(buffer.typeParams.isEmpty)
        #expect(!buffer.hasPrimaryConstructorSyntax)
        #expect(buffer.primaryConstructorParams.isEmpty)
        #expect(buffer.secondaryConstructors.isEmpty)

        let supertypePaths = try buffer.superTypeEntries.map {
            try namedTypePath($0.typeRef, ast: ast, context: context)
        }
        #expect(supertypePaths == [["Source"], ["Sink"]])
        #expect(buffer.superTypeEntries.allSatisfy { $0.delegateExpression == nil && $0.constructorArgs.isEmpty })
    }

    @Test
    func importedKlibExposesTheFinalPublicTypeAndConstructor() throws {
        let selectedLibrary = try libraryArtifactURL().path
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(
            inputs: [inputPath],
            moduleName: "KotlinxIOBufferShapeConsumer",
            stdlibLibraryPath: selectedLibrary,
            allowDefaultStdlibLibrary: false
        )
        _ = context.sourceManager.addFile(
            path: inputPath,
            contents: Data("import kotlinx.io.Buffer\nfun makeBuffer(): Buffer = Buffer()".utf8)
        )
        #expect(context.options.stdlibLibraryPath == selectedLibrary)
        try runSema(context)
        #expect(context.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
                "\(context.diagnostics.diagnostics)")

        let sema = try #require(context.sema)
        let interner = context.interner
        let bufferPath = ["kotlinx", "io", "Buffer"].map(interner.intern)
        let bufferID = try #require(sema.symbols.lookup(fqName: bufferPath))
        let buffer = try #require(sema.symbols.symbol(bufferID))
        #expect(buffer.kind == .class)
        #expect(buffer.visibility == .public)
        #expect(!buffer.flags.contains(.openType))
        #expect(!buffer.flags.contains(.abstractType))
        #expect(buffer.flags.contains(.importedLibrary))

        let actualSupertypes = sema.symbols.directSupertypes(for: bufferID).compactMap {
            sema.symbols.symbol($0)?.fqName.map(interner.resolve).joined(separator: ".")
        }.sorted()
        #expect(actualSupertypes == ["kotlin.Any", "kotlinx.io.Sink", "kotlinx.io.Source"])

        let constructorIDs = sema.symbols.lookupAll(fqName: bufferPath + [interner.intern("<init>")])
            .filter { sema.symbols.symbol($0)?.kind == .constructor }
        try #require(constructorIDs.count == 1, "Expected one zero-argument Buffer constructor")
        let constructorID = try #require(constructorIDs.first)
        let constructor = try #require(sema.symbols.symbol(constructorID))
        let signature = try #require(sema.symbols.functionSignature(for: constructorID))
        #expect(sema.symbols.parentSymbol(for: constructorID) == bufferID)
        #expect(constructor.visibility == .public)
        #expect(constructor.flags.contains(.importedLibrary))
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.valueParameterSymbols.isEmpty)
    }

    @Test
    func generatedKlibRetainsExactBufferClassAndConstructorMetadata() throws {
        let artifact = try libraryArtifactURL()
        let manifestData = try Data(contentsOf: artifact.appendingPathComponent("manifest.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
        #expect(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())

        let metadata = try Data(contentsOf: artifact.appendingPathComponent("metadata.bin"))
        let records = MetadataDecoder().decode(metadata)
        let classRecords = records.filter { $0.fqName == bufferFQName && $0.kind == .class }
        try #require(classRecords.count == 1)
        let buffer = try #require(classRecords.first)
        #expect(buffer.visibility == .public)
        #expect(buffer.modality == .final)
        #expect(!buffer.isOpenClass)
        #expect(Set((buffer.superFQName ?? "").split(separator: ",").map(String.init))
            == Set(["kotlin.Any", "kotlinx.io.Source", "kotlinx.io.Sink"]))

        let constructorRecords = records.filter {
            $0.fqName == constructorFQName && $0.kind == .constructor
        }
        try #require(constructorRecords.count == 1)
        let constructor = try #require(constructorRecords.first)
        #expect(constructor.visibility == .public)
        #expect(constructor.arity == 0)
        #expect(constructor.valueParameterNames.isEmpty)
        #expect(constructor.valueParameterHasDefaultValues.isEmpty)
    }
}
#endif
