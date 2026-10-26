@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct AnnotationDefaultImportResolutionTests {
    @Test
    func bundledJvmFieldAnnotationsResolveThroughDefaultImports() throws {
        let source = """
        class C { @Volatile var v = 1; @Transient var t = 2 }
        """
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuu-3475-\(UUID().uuidString).kt").path
        let context = CompilerDriver().runFrontend(
            options: CompilerOptions(
                moduleName: "KUU3475",
                inputs: [input],
                outputPath: input + ".out",
                emit: .kirDump,
                target: TargetTriple.hostDefault(),
                allowDefaultStdlibLibrary: false
            ),
            inMemorySources: [input: Data(source.utf8)]
        ).context

        #expect(!context.diagnostics.hasError, "Unexpected diagnostics: \(context.diagnostics.diagnostics)")
        let sema = try #require(context.sema)
        let ast = try #require(context.ast)
        let fileID = try #require(context.sourceManager.fileID(forPath: input))
        let file = try #require(ast.file(for: fileID))
        for (name, expectedFQName) in [("Volatile", "kotlin.jvm.Volatile"), ("Transient", "kotlin.jvm.Transient")] {
            let resolved = resolveAnnotationSymbol(
                named: name,
                in: file,
                symbols: sema.symbols,
                interner: context.interner
            )
            let expected = expectedFQName.split(separator: ".").map { context.interner.intern(String($0)) }
            #expect(resolved == sema.symbols.lookup(fqName: expected))
        }
    }

    @Test(arguments: [false, true])
    func defaultImportPrecedesUnrelatedShortName(reverseOrder: Bool) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        let names = reverseOrder
            ? ["kotlin.jvm.Volatile", "kotlin.concurrent.Volatile"]
            : ["kotlin.concurrent.Volatile", "kotlin.jvm.Volatile"]
        for name in names { define(name, symbols: symbols, interner: interner) }
        let file = makeFile(package: "client", interner: interner)
        for fallback in [false, true] {
            let resolved = resolveAnnotationSymbol(
                named: "Volatile", in: file, symbols: symbols, interner: interner,
                allowGlobalShortNameFallback: fallback
            )
            #expect(resolved == symbols.lookup(fqName: ["kotlin", "jvm", "Volatile"].map(interner.intern)))
        }
    }

    @Test(arguments: ["named", "alias", "wildcard", "package", "lexical"])
    func explicitAndLexicalNamesRetainPriority(kind: String) {
        let interner = StringInterner()
        let symbols = SymbolTable()
        define("kotlin.jvm.Volatile", symbols: symbols, interner: interner)
        if kind == "lexical" { define("client.Owner", kind: .class, symbols: symbols, interner: interner) }
        let expected = kind == "package" ? "client.Volatile"
            : kind == "lexical" ? "client.Owner.Volatile"
            : kind == "alias" ? "custom.Marker" : "custom.Volatile"
        define(expected, symbols: symbols, interner: interner)
        let imports: [ImportDecl]
        switch kind {
        case "named", "alias", "wildcard":
            let location = SourceLocation(file: .invalid, offset: 0)
            imports = [ImportDecl(
                range: SourceRange(start: location, end: location),
                path: (kind == "wildcard" ? ["custom"] : ["custom", kind == "alias" ? "Marker" : "Volatile"]).map(interner.intern),
                alias: kind == "alias" ? interner.intern("Volatile") : nil,
                isWildcard: kind == "wildcard"
            )]
        default:
            imports = []
        }
        let resolved = resolveAnnotationSymbol(
            named: "Volatile",
            in: makeFile(package: "client", imports: imports, interner: interner),
            symbols: symbols, interner: interner,
            enclosingFQName: kind == "lexical" ? ["client", "Owner"].map(interner.intern) : []
        )
        #expect(resolved == symbols.lookup(fqName: expected.split(separator: ".").map { interner.intern(String($0)) }))
    }

    @discardableResult
    private func define(_ name: String, kind: SymbolKind = .annotationClass, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let path = name.split(separator: ".").map { interner.intern(String($0)) }
        for count in 1..<path.count {
            let prefix = Array(path.prefix(count))
            if symbols.lookup(fqName: prefix) == nil {
                _ = symbols.define(kind: .package, name: prefix.last!, fqName: prefix, declSite: nil, visibility: .public)
            }
        }
        return symbols.define(kind: kind, name: path.last!, fqName: path, declSite: nil, visibility: .public)
    }

    private func makeFile(package: String, imports: [ImportDecl] = [], interner: StringInterner) -> ASTFile {
        ASTFile(fileID: .invalid, packageFQName: [interner.intern(package)], imports: imports,
                topLevelDecls: [], scriptBody: [])
    }
}
