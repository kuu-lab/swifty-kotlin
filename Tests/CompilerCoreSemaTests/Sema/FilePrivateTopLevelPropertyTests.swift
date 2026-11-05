#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct FilePrivateTopLevelPropertyTests {
    @Test(arguments: ["", "package demo\n"], ["private val", "private var", "private const val"])
    func propertiesBindToTheirOwnFile(package: String, declaration: String) throws {
        let expectedValues = ["f1", "f2-diff"]
        let sources = [
            "\(package)\(declaration) secret = \"\(expectedValues[0])\"\nfun useSecret(): String = secret",
            "\(package)\(declaration) secret = \"\(expectedValues[1])\"\nfun useLocal(): String = secret",
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
                for (path, expectedValue) in zip(paths, expectedValues) {
                    let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
                    let property = try #require(properties.first { sema.symbols.sourceFileID(for: $0) == fileID })
                    #expect(constants[property] == .stringLiteral(ctx.interner.intern(expectedValue)))
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

    /// KUU-4312: an unqualified reference to a file-private top-level
    /// property from another file is unresolved (the declaration is not a
    /// candidate), while the qualified `demo.secret` spelling still reports
    /// the private-access error, matching kotlinc's "private in file".
    @Test(arguments: [
        ("secret", "KSWIFTK-SEMA-0022"),
        ("demo.secret", "KSWIFTK-SEMA-0040"),
    ])
    func anotherFileCannotAccessPrivateProperty(reference: String, expectedCode: String) throws {
        try withTemporaryFiles(contents: [
            "package demo\nprivate val secret = 1",
            "package demo\nfun use(): Int = \(reference)",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == expectedCode })
        }
    }

    /// KUU-4312: a file-private top-level declaration in another file of the
    /// same package is not a resolution candidate, so a wildcard-imported
    /// enum entry with the same name wins instead of the use site reporting
    /// SEMA-0040.
    @Test
    func filePrivateTopLevelDeclDoesNotShadowWildcardImportedEnumEntry() throws {
        let sources = [
            """
            package demo

            private val SUSPEND = "hidden"
            """,
            """
            package demo

            enum class BufferOverflow { SUSPEND, DROP_OLDEST, DROP_LATEST }
            """,
            """
            package demo
            import demo.BufferOverflow.*

            fun check(): BufferOverflow = SUSPEND
            fun checkOldest(): BufferOverflow = DROP_OLDEST
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let intern = ctx.interner.intern
            let entry = try #require(sema.symbols.lookup(fqName: [
                intern("demo"), intern("BufferOverflow"), intern("SUSPEND"),
            ]))
            let hidden = try #require(sema.symbols.lookup(fqName: [
                intern("demo"), intern("SUSPEND"),
            ]))
            let boundSymbols = Set(sema.bindings.identifierSymbols.values)
            #expect(boundSymbols.contains(entry))
            #expect(!boundSymbols.contains(hidden))
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
