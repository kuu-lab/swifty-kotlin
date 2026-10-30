@testable import CompilerCore
@testable import CompilerTestSupport
import Testing
import TestStdlibCache

@Suite
struct EnumEntryImportResolutionTests {
    private let enumSource = """
    package tokens
    enum class Kind { PLUS, MINUS }
    """

    private func checkImportSources(
        _ sources: [String],
        body: (CompilationContext) throws -> Void
    ) throws {
        TestStdlibCache.shared.prepare()
        let artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths, stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
            )
            #expect(!ctx.options.includeStdlib)
            try runSema(ctx)
            try body(ctx)
        }
    }

    @Test
    func wildcardImportsEntriesIntoOnlyTheConsumerFile() throws {
        let ctx = makeContextFromSources([
            enumSource,
            """
            import tokens.Kind.*
            fun main(){println(PLUS);println(when(PLUS){PLUS->3;MINUS->-3})}
            """,
            "package unrelated\nfun marker() = 0",
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let scopes = TypeCheckScopeBuilder().buildFileScopes(
            ast: ast, sema: sema, interner: ctx.interner, sourceManager: ctx.sourceManager
        )
        let consumerID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[1]))
        let unrelatedID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[2]))
        let consumer = try #require(scopes[consumerID.rawValue])
        let unrelated = try #require(scopes[unrelatedID.rawValue])
        for name in ["PLUS", "MINUS"] {
            let internedName = ctx.interner.intern(name)
            let entry = sema.symbols.lookupAll(fqName: ["tokens", "Kind", name].map(ctx.interner.intern))
            #expect(entry.count == 1)
            #expect(consumer.lookup(internedName) == entry)
            #expect(unrelated.lookup(internedName).isEmpty)
        }
        #expect(consumer.lookup(ctx.interner.intern("Kind")).isEmpty)
    }

    @Test(arguments: [
        "import tokens.Kind.PLUS\nfun choose() = when(PLUS){PLUS->3;tokens.Kind.MINUS->-3}",
        "import tokens.Kind.PLUS as positive\nfun choose() = when(positive){positive->3;tokens.Kind.MINUS->-3}",
        "import tokens.Kind\nfun choose() = when(Kind.PLUS){Kind.PLUS->3;Kind.MINUS->-3}",
    ])
    func explicitAliasedAndQualifiedEntriesRemainValid(consumer: String) throws {
        let ctx = makeContextFromSources([enumSource, consumer])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun choose() = PLUS",
        "import tokens.*\nfun choose() = PLUS",
        "import tokens.Kind\nfun choose() = PLUS",
        "import tokens.Kind.PLUS\nfun choose() = MINUS",
        "import tokens.Kind.PLUS as positive\nfun choose() = PLUS",
    ])
    func entriesRequireAnEntryImport(consumer: String) throws {
        let ctx = makeContextFromSources([enumSource, consumer])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0022" && $0.message.contains("Unresolved reference")
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func wildcardImportDoesNotMakeIncompleteWhenExhaustive() throws {
        let ctx = makeContextFromSources([
            enumSource,
            """
            import tokens.Kind.*
            fun choose(value: tokens.Kind): Int = when(value){PLUS->3}
            """,
        ])
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0004")
    }

    @Test
    func sameNameEntriesFromTwoWildcardImportsAreAmbiguous() throws {
        let ctx = makeContextFromSources([
            enumSource,
            "package other\nenum class Kind { PLUS, OTHER }",
            """
            import tokens.Kind.*
            import other.Kind.*
            fun choose(): tokens.Kind = PLUS
            """,
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0003" && $0.message == "Ambiguous reference 'PLUS'."
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitAndLocalBindingsKeepPriorityOverWildcardEntries() throws {
        let ctx = makeContextFromSources([
            enumSource,
            "package other\nenum class Kind { PLUS, OTHER }",
            """
            import tokens.Kind.*
            import other.Kind.*
            import other.Kind.PLUS
            fun choose(): other.Kind = PLUS
            fun local(): Int { val PLUS = 7; return PLUS }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func wildcardImportDoesNotExposeEntriesOfPrivateEnum() throws {
        let ctx = makeContextFromSources([
            "package tokens\nprivate enum class Secret { HIDDEN }",
            "import tokens.Secret.*\nfun choose() = HIDDEN",
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let scopes = TypeCheckScopeBuilder().buildFileScopes(
            ast: try #require(ctx.ast), sema: sema, interner: ctx.interner,
            sourceManager: ctx.sourceManager
        )
        let consumerID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[1]))
        let consumer = try #require(scopes[consumerID.rawValue])
        #expect(consumer.lookup(ctx.interner.intern("HIDDEN")).isEmpty)
    }

    @Test(arguments: [false, true])
    func linkedExpectActualEntriesAreOneImportCandidate(isWildcard: Bool) throws {
        try checkImportSources([
            "package paired\nexpect enum class Kind { PLUS; fun marker(): Int }",
            "package paired\nactual enum class Kind { PLUS; actual fun marker(): Int = 3 }",
            """
            import paired.Kind.\(isWildcard ? "*" : "PLUS")
            fun choose(): Int = PLUS.marker()
            """,
        ]) { ctx in
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func nestedEnumImportsRespectContainingClassVisibility(privateOwner: Bool) throws {
        try checkImportSources([
            "package nested\n\(privateOwner ? "private " : "")class Container { enum class Kind { PLUS } }",
            "import nested.Container.Kind.*\nfun choose(): Int = when(PLUS){PLUS->3}",
        ]) { ctx in
            #expect(ctx.diagnostics.hasError == privateOwner, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func privateEnumEntriesCanBeImportedWithinTheirFile() throws {
        try checkImportSources([
            """
            package tokens
            import tokens.Secret.*
            private enum class Secret { HIDDEN }
            fun choose(): Int = when(HIDDEN){HIDDEN->3}
            """,
        ]) { ctx in
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func wildcardImportDoesNotIntroduceInstanceOrCompanionMembers() throws {
        try checkImportSources([
            """
            package tokens
            enum class Kind {
                PLUS, MINUS;
                val code: Int = 3
                fun marker(): Int = 3
                companion object { val label: Int = 1; fun count(): Int = 2 }
            }
            """,
            "import tokens.Kind.*\nfun choose(): Int = when(PLUS){PLUS->3;MINUS->-3}",
        ]) { ctx in
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let scopes = TypeCheckScopeBuilder().buildFileScopes(
                ast: try #require(ctx.ast), sema: sema, interner: ctx.interner,
                sourceManager: ctx.sourceManager
            )
            let consumerID = try #require(ctx.sourceManager.fileID(forPath: ctx.options.inputs[1]))
            let consumer = try #require(scopes[consumerID.rawValue])
            let enumPath = ["tokens", "Kind"].map(ctx.interner.intern)
            for name in ["code", "marker", "label", "count", "values", "entries", "valueOf"] {
                let candidates = consumer.lookup(ctx.interner.intern(name))
                #expect(candidates.allSatisfy { id in
                    guard let symbol = sema.symbols.symbol(id) else { return false }
                    return Array(symbol.fqName.prefix(enumPath.count)) != enumPath
                })
            }
        }
    }
}
