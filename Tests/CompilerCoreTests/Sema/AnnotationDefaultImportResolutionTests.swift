@testable import CompilerCore
import Testing

@Suite
struct AnnotationDefaultImportResolutionTests {
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
        let expected = kind == "package" ? "client.Volatile"
            : kind == "lexical" ? "client.Owner.Volatile" : "custom.Volatile"
        define(expected, symbols: symbols, interner: interner)
        let imports: [ImportDecl]
        switch kind {
        case "named", "alias", "wildcard":
            let location = SourceLocation(file: .invalid, offset: 0)
            imports = [ImportDecl(
                range: SourceRange(start: location, end: location),
                path: (kind == "wildcard" ? ["custom"] : ["custom", "Volatile"]).map(interner.intern),
                alias: kind == "alias" ? interner.intern("Mark") : nil,
                isWildcard: kind == "wildcard"
            )]
        default:
            imports = []
        }
        let resolved = resolveAnnotationSymbol(
            named: kind == "alias" ? "Mark" : "Volatile",
            in: makeFile(package: "client", imports: imports, interner: interner),
            symbols: symbols, interner: interner,
            enclosingFQName: kind == "lexical" ? ["client", "Owner"].map(interner.intern) : []
        )
        #expect(resolved == symbols.lookup(fqName: expected.split(separator: ".").map { interner.intern(String($0)) }))
    }

    @discardableResult
    private func define(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID {
        let path = name.split(separator: ".").map { interner.intern(String($0)) }
        return symbols.define(kind: .annotationClass, name: path.last!, fqName: path, declSite: nil, visibility: .public)
    }

    private func makeFile(package: String, imports: [ImportDecl] = [], interner: StringInterner) -> ASTFile {
        ASTFile(fileID: .invalid, packageFQName: [interner.intern(package)], imports: imports,
                topLevelDecls: [], scriptBody: [])
    }
}
