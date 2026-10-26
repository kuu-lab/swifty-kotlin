@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeCheckScopeBuilderTests {
    private func importVisibilityContext(_ sources: [String]) -> CompilationContext {
        let context = makeContextFromSources(sources)
        var options = context.options
        options.includeStdlib = false
        return CompilationContext(
            options: options, sourceManager: context.sourceManager,
            diagnostics: context.diagnostics, interner: context.interner
        )
    }

    @Test(arguments: [false, true])
    func unusedPrivateImportsAreRejectedWithoutHidingPublicOverloads(aliases: Bool) throws {
        let classAlias = aliases ? " as HiddenAlias" : ""
        let functionAlias = aliases ? " as hiddenAlias" : ""
        let ctx = importVisibilityContext([
            """
            package secret
            private class Hidden
            private fun hidden() {}
            fun mixed() {}
            private fun mixed(value: Int) {}
            """,
            """
            package app
            import secret.Hidden\(classAlias)
            import secret.hidden\(functionAlias)
            import secret.mixed
            fun main() { mixed() }
            """,
        ])
        do { try runSema(ctx) } catch {}
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 2, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0040" }, "\(errors)")
        let lines = Set(errors.compactMap { $0.primaryRange?.start }.map {
            ctx.sourceManager.lineColumn(of: $0).line
        })
        #expect(lines == [2, 3])
    }

    @Test
    func sameFilePrivateImportIsAllowed() throws {
        let ctx = importVisibilityContext([
            "package secret\nimport secret.hidden\nprivate fun hidden() {}\nfun main() {}",
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inaccessibleWildcardMemberDoesNotShadowDefaultImport() throws {
        let ctx = makeContextFromSources([
            "package kotlin\nfun answer(): Int = 1",
            "package imported\nprivate fun answer(): Int = 2",
            "package app\nimport imported.*\nfun consume(): Int = answer()",
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let scopes = TypeCheckScopeBuilder().buildFileScopes(
            ast: ast, sema: sema, interner: ctx.interner, sourceManager: ctx.sourceManager
        )
        let appFile = try #require(ast.sortedFiles.first {
            $0.packageFQName == [ctx.interner.intern("app")]
        })
        let scope = try #require(scopes[appFile.fileID.rawValue])
        let answer = ctx.interner.intern("answer")
        #expect(scope.lookup(answer) == sema.symbols.lookupAll(fqName: [ctx.interner.intern("kotlin"), answer]))
    }

    @Test(arguments: [false, true])
    func enumEntriesRequiresAnExplicitImportEvenWithOptIn(optIn: Bool) throws {
        let annotation = optIn ? "@OptIn(ExperimentalStdlibApi::class)\n" : ""
        try withTemporaryFile(contents: """
        enum class Color { RED, GREEN, BLUE }
        \(annotation)fun useEntries() = enumEntries<Color>()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.contains {
                    $0.severity == .error && $0.message.contains("enumEntries")
                },
                "Unqualified enumEntries should not be available without importing kotlin.enums: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func defaultImportsPreserveFileSpecificShadowingAndAliases() throws {
        let sources = [
            """
            package kotlin
            class ScopeChoice
            class ScopeDefaultOnly
            """,
            """
            package imported
            class ScopeChoice
            class ScopeImportedOnly
            """,
            """
            package explicitUse
            import imported.ScopeChoice
            import imported.ScopeImportedOnly as LocalAlias
            fun choose(value: ScopeChoice): ScopeChoice = value
            fun alias(value: LocalAlias): LocalAlias = value
            """,
            """
            package wildcardUse
            import imported.*
            fun choose(value: ScopeChoice): ScopeChoice = value
            """,
            """
            package defaultUse
            fun choose(value: ScopeChoice): ScopeChoice = value
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let scopes = TypeCheckScopeBuilder().buildFileScopes(
                ast: try #require(ctx.ast), sema: sema, interner: ctx.interner
            )
            let fileScopes = try paths.map { path in
                let fileID = try #require(ctx.sourceManager.fileID(forPath: path))
                return try #require(scopes[fileID.rawValue])
            }
            let choice = ctx.interner.intern("ScopeChoice")
            let defaultChoice = sema.symbols.lookupAll(fqName: [ctx.interner.intern("kotlin"), choice])
            let importedChoice = sema.symbols.lookupAll(fqName: [ctx.interner.intern("imported"), choice])
            let importedOnly = sema.symbols.lookupAll(
                fqName: [ctx.interner.intern("imported"), ctx.interner.intern("ScopeImportedOnly")]
            )
            #expect(defaultChoice.count == 1)
            #expect(importedChoice.count == 1)
            #expect(importedOnly.count == 1)
            #expect(fileScopes[2].lookup(choice) == importedChoice)
            #expect(fileScopes[3].lookup(choice) == importedChoice)
            #expect(fileScopes[4].lookup(choice) == defaultChoice)
            #expect(fileScopes[2].lookup(ctx.interner.intern("LocalAlias")) == importedOnly)
            #expect(fileScopes[3].lookup(ctx.interner.intern("LocalAlias")).isEmpty)
            #expect(fileScopes[4].lookup(ctx.interner.intern("ScopeImportedOnly")).isEmpty)
            #expect(fileScopes[4].lookup(ctx.interner.intern("LocalAlias")).isEmpty)
            #expect(fileScopes[2].lookupMergingChain(choice) == importedChoice + defaultChoice)
            let defaultOnly = sema.symbols.lookupAll(
                fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("ScopeDefaultOnly")]
            )
            #expect(defaultOnly.count == 1)
            for scope in fileScopes[2 ... 4] {
                #expect(scope.lookup(ctx.interner.intern("ScopeDefaultOnly")) == defaultOnly)
            }

            // Adding a file-local binding must not affect another file's defaults.
            let localChoice = sema.symbols.define(
                kind: .local, name: choice, fqName: [ctx.interner.intern("local"), choice],
                declSite: nil, visibility: .private
            )
            fileScopes[2].insert(localChoice)
            #expect(fileScopes[2].lookup(choice) == [localChoice])
            #expect(fileScopes[4].lookup(choice) == defaultChoice)
        }
    }

    @Test
    func defaultImportsDoNotLeakBetweenCompilations() throws {
        let builder = TypeCheckScopeBuilder()
        for (index, name) in ["FirstDefault", "SecondDefault", "FirstDefault"].enumerated() {
            let absentName = name == "FirstDefault" ? "SecondDefault" : "FirstDefault"
            try withTemporaryFiles(contents: ["package kotlin\nclass \(name)", "package app"]) { paths in
                // Vary interned IDs so a stale scope cannot accidentally match
                // the next compilation's names at the same numeric positions.
                let interner = StringInterner()
                for offset in 0 ..< index * 7 {
                    _ = interner.intern("preexisting-\(offset)")
                }
                let ctx = makeCompilationContext(inputs: paths, includeStdlib: false, interner: interner)
                try runSema(ctx)
                #expect(!ctx.diagnostics.hasError)
                let sema = try #require(ctx.sema)
                let scopes = builder.buildFileScopes(
                    ast: try #require(ctx.ast), sema: sema, interner: ctx.interner
                )
                let fileID = try #require(ctx.sourceManager.fileID(forPath: paths[1]))
                let scope = try #require(scopes[fileID.rawValue])
                let expected = sema.symbols.lookupAll(
                    fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern(name)]
                )
                #expect(expected.count == 1)
                #expect(scope.lookup(ctx.interner.intern(name)) == expected)
                #expect(scope.lookup(ctx.interner.intern(absentName)).isEmpty)
            }
        }
    }
}
