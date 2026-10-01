@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct ImportedMetadataVisibilityTests {
    @Test
    func visibilitySurvivesMetadataRoundTripAndLegacyDefaultsPublic() throws {
        let records = [
            MetadataRecord(kind: .function, visibility: .internal, mangledName: "internalFn", fqName: "demo.internalFn"),
            MetadataRecord(kind: .property, visibility: .private, mangledName: "secret", fqName: "demo.secret"),
            MetadataRecord(kind: .class, visibility: .protected, mangledName: "Nested", fqName: "demo.Nested"),
            MetadataRecord(kind: .function, mangledName: "publicFn", fqName: "demo.publicFn"),
        ]
        let text = MetadataEncoder().serialize(records)
        let decoded = MetadataDecoder().decode(text)
        #expect(decoded.map(\.visibility) == [.internal, .private, .protected, .public])
        #expect(!text.contains("visibility=public"))

        let old = MetadataDecoder().decode("symbols=1\nfunction old fq=demo.old schema=v1 arity=0")
        #expect(try #require(old.first).visibility == .public)
        let invalid = MetadataDecoder().decode("symbols=1\nfunction invalid fq=demo.invalid schema=v1 visibility=invalid")
        #expect(try #require(invalid.first).visibility == .private)
    }

    @Test
    func importedInternalAndPrivateCannotBeCalledFromClient() {
        let symbols = SymbolTable()
        let interner = StringInterner()
        let file = FileID(rawValue: 100)
        func imported(_ name: String, _ visibility: Visibility) -> SemanticSymbol {
            let interned = interner.intern(name)
            let id = symbols.define(
                kind: .function,
                name: interned,
                fqName: [interned],
                declSite: nil,
                visibility: visibility,
                flags: [.importedLibrary]
            )
            return symbols.symbol(id)!
        }
        let checker = VisibilityChecker(symbols: symbols)
        #expect(checker.isAccessible(imported("publicFn", .public), fromFile: file, enclosingClass: nil))
        #expect(!checker.isAccessible(imported("internalFn", .internal), fromFile: file, enclosingClass: nil))
        #expect(!checker.isAccessible(imported("privateFn", .private), fromFile: file, enclosingClass: nil))
        let suppressed = VisibilityChecker(symbols: symbols, invisibleAccessFiles: [file.rawValue])
        #expect(suppressed.isAccessible(imported("publishedApi", .internal), fromFile: file, enclosingClass: nil))

        let className = interner.intern("Hidden")
        let hiddenClass = symbols.define(
            kind: .class, name: className, fqName: [className],
            declSite: nil, visibility: .internal, flags: [.importedLibrary]
        )
        let ctorName = interner.intern("<init>")
        let constructor = symbols.define(
            kind: .constructor, name: ctorName, fqName: [className, ctorName],
            declSite: nil, visibility: .public, flags: [.importedLibrary]
        )
        symbols.setParentSymbol(hiddenClass, for: constructor)
        #expect(!checker.isAccessible(symbols.symbol(constructor)!, fromFile: file, enclosingClass: nil))
    }

    @Test
    func importedStdlibTypesCannotBeNamedOrInheritedByClient() throws {
        TestStdlibCache.shared.prepare()
        let sources = [
            "private fun probe(x: kotlin.ranges.IntProgressionIterator): Any = x",
            "abstract class Leak : kotlin.native.ref.WeakReferenceImpl()",
        ]
        for source in sources {
            try withTemporaryFiles(contents: [source]) { paths in
                let ctx = makeCompilationContext(
                    inputs: paths, emit: .executable, allowDefaultStdlibLibrary: true
                )
                try runSema(ctx)
                #expect(ctx.options.stdlibLibraryPath != nil)
                #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0044" },
                        "\(ctx.diagnostics.diagnostics)")
            }
        }
    }
}
