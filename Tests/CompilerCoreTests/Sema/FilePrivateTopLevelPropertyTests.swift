#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FilePrivateTopLevelPropertyTests {
    @Test(arguments: ["", "package demo\n"], ["private val", "private var", "private const val"])
    func propertiesBindToTheirOwnFile(package: String, declaration: String) throws {
        let sources = [
            "\(package)\(declaration) secret = \"f1\"\nfun useSecret(): String = secret",
            "\(package)\(declaration) secret = \"f2-diff\"\nfun useLocal(): String = secret",
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let properties = sema.symbols.lookupByShortName(ctx.interner.intern("secret"))
                .filter { sema.symbols.symbol($0)?.kind == .property }
            #expect(properties.count == 2)
            #expect(Set(properties.compactMap { sema.symbols.sourceFileID(for: $0) }).count == 2)
            let references = sema.bindings.identifierSymbols.values.filter { properties.contains($0) }
            #expect(Set(references) == Set(properties))
            if declaration != "private var" {
                let constants = ConstantCollector().collectPropertyConstantInitializers(
                    ast: try #require(ctx.ast), sema: sema, interner: ctx.interner, sourceByFileID: [:]
                )
                for (index, path) in paths.enumerated() {
                    let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
                    let property = try #require(properties.first { sema.symbols.sourceFileID(for: $0) == fileID })
                    #expect(constants[property] == .stringLiteral(ctx.interner.intern(index == 0 ? "f1" : "f2-diff")))
                }
            }
        }
    }

    @Test(arguments: ["val", "internal val", "private val"])
    func declarationsInSameScopeStillConflict(declaration: String) throws {
        let sources = declaration == "private val"
            ? ["private val secret = 1\nprivate val secret = 2"]
            : ["\(declaration) secret = 1", "\(declaration) secret = 2"]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
        }
    }

    @Test(arguments: ["secret", "demo.secret"])
    func anotherFileCannotAccessPrivateProperty(reference: String) throws {
        try withTemporaryFiles(contents: [
            "package demo\nprivate val secret = 1",
            "package demo\nfun use(): Int = \(reference)",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
        }
    }

    @Test(arguments: [false, true])
    func privateAndPublicPropertiesStillConflict(reverse: Bool) throws {
        var sources = [
            "package demo\nval secret = 1\nfun publicUse(): Int = secret",
            "package demo\nprivate val secret = 2\nfun privateUse(): Int = secret",
            "package demo\nfun otherUse(): Int = secret",
        ]
        if reverse { sources.reverse() }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0001" })
        }
    }
}
#endif
