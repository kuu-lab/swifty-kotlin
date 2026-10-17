@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOFileMetadataContractTests {
    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let artifact: String? = library ? CompilerOptions.defaultStdlibLibraryPath : nil
        if let artifact {
            let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                URL(fileURLWithPath: artifact).appendingPathComponent("manifest.json"))) as? [String: Any])
            try #require(manifest["moduleName"] as? String == "KSwiftKStdlib")
            try #require(manifest["kotlinLanguageVersion"] as? String == "2.4.20")
            try #require(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash())
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let result = makeCompilationContext(inputs: [path], stdlibLibraryPath: artifact,
                                            allowDefaultStdlibLibrary: false)
        _ = result.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(result.options.includeStdlib == !library)
        try #require(result.options.stdlibLibraryPath == artifact)
        return result
    }

    @Test(arguments: [false, true])
    func fileMetadataHasPublicFinalShapeAndOneDefaultedPrimaryConstructor(library: Bool) throws {
        let ctx = try context("""
        package kuu2626.consumer
        import kotlinx.io.files.FileMetadata

        fun fileMetadataProbe(): FileMetadata {
            FileMetadata(true, false, 41L)
            FileMetadata()
            return FileMetadata(isDirectory = true)
        }
        """, library: library)
        try runSema(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let symbols = sema.symbols
        let ownerFQName = ["kotlinx", "io", "files", "FileMetadata"].map { ctx.interner.intern($0) }
        let ownerID = try #require(symbols.lookup(fqName: ownerFQName))
        let owner = try #require(symbols.symbol(ownerID))
        #expect(owner.kind == .class)
        #expect(owner.visibility == .public)
        #expect(!owner.flags.contains(.openType))
        #expect(!owner.flags.contains(.abstractType))
        #expect(!owner.flags.contains(.sealedType))
        #expect(owner.flags.contains(.importedLibrary) == library)

        let ownerType = sema.types.make(.classType(ClassType(classSymbol: ownerID, args: [], nullability: .nonNull)))
        let constructors = symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern("<init>")])
            .compactMap { symbols.symbol($0) }.filter { $0.kind == .constructor }
        try #require(constructors.count == 1, "KLIB/source shape keeps one primary constructor with defaults")
        let constructor = try #require(constructors.first)
        let signature = try #require(symbols.functionSignature(for: constructor.id))
        let parameterNames = signature.valueParameterSymbols.compactMap { symbols.symbol($0).map { ctx.interner.resolve($0.name) } }
        #expect(constructor.visibility == .public)
        #expect(constructor.flags.contains(.importedLibrary) == library)
        #expect(signature.receiverType == ownerType && signature.returnType == ownerType)
        #expect(parameterNames == ["isRegularFile", "isDirectory", "size"])
        #expect(signature.parameterTypes == [sema.types.booleanType, sema.types.booleanType, sema.types.longType])
        #expect(signature.valueParameterHasDefaultValues == [true, true, true])
        #expect(signature.valueParameterIsVararg == [false, false, false])

        for (name, type) in [("isRegularFile", sema.types.booleanType),
                             ("isDirectory", sema.types.booleanType),
                             ("size", sema.types.longType)] {
            let matches = symbols.lookupAll(fqName: ownerFQName + [ctx.interner.intern(name)])
                .compactMap { symbols.symbol($0) }.filter { $0.kind == .property }
            try #require(matches.count == 1, "FileMetadata exposes exactly one \(name) property")
            let property = try #require(matches.first)
            #expect(property.visibility == .public)
            #expect(property.flags.contains(.importedLibrary) == library)
            #expect(!property.flags.contains(.mutable))
            #expect(symbols.propertyType(for: property.id) == type)
        }

        if library {
            let artifact = try #require(ctx.options.stdlibLibraryPath)
            let records = MetadataDecoder().decode(try Data(contentsOf:
                URL(fileURLWithPath: artifact).appendingPathComponent("metadata.bin")))
            let classRecord = try #require(records.first {
                $0.kind == .class && $0.fqName == "kotlinx.io.files.FileMetadata"
            })
            #expect(classRecord.visibility == .public)
            #expect(classRecord.modality == .final && !classRecord.isOpenClass)
            let constructorRecord = try #require(records.first {
                $0.kind == .constructor && $0.fqName == "kotlinx.io.files.FileMetadata.<init>"
            })
            #expect(constructorRecord.visibility == .public)
            #expect(constructorRecord.arity == 3)
            #expect(constructorRecord.valueParameterNames == ["isRegularFile", "isDirectory", "size"])
            #expect(constructorRecord.valueParameterHasDefaultValues == [true, true, true])
            for name in ["isRegularFile", "isDirectory", "size"] {
                let propertyRecord = try #require(records.first {
                    $0.kind == .property && $0.fqName == "kotlinx.io.files.FileMetadata." + name
                })
                #expect(propertyRecord.visibility == .public)
                #expect(propertyRecord.modality == .final && !propertyRecord.isMutable)
            }
        }
    }

    @Test(arguments: [false, true])
    func fileMetadataIsRejectedAsASuperclass(library: Bool) throws {
        let ctx = try context("""
        package kuu2626.consumer
        import kotlinx.io.files.FileMetadata

        class IllegalFileMetadataSubclass : FileMetadata()
        """, library: library)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
