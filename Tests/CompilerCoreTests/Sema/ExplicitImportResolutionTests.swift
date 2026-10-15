#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

@Suite
struct ExplicitImportResolutionTests {
    /// KUU-2068: adding a packaged singleton must not expose its bare value
    /// through the global classifier index in unrelated files.
    @Test(arguments: ["", "package sample", "import sample.*", "import sample.Utility", "import sample.Utility as Alias"])
    func packagedObjectValuesRequireLexicalImports(importDirective: String) throws {
        let owner = """
        package sample
        object Utility { fun compare(a: Any?, b: Any?): Boolean = a === b }
        """
        let name = importDirective.contains("as Alias") ? "Alias" : "Utility"
        let usage = """
        \(importDirective)
        fun same(a: Any?, b: Any?): Boolean = \(name).compare(a, b)
        fun qualified(a: Any?, b: Any?): Boolean = sample.Utility.compare(a, b)
        """
        try withTemporaryFiles(contents: [owner, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try? runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            if importDirective.isEmpty {
                #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0022" && $0.message.contains("Utility") })
            } else {
                #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
            }
        }
    }

    private func context(inputs: [String], useArtifact: Bool) throws -> CompilationContext {
        let artifact: String?
        if useArtifact {
            TestStdlibCache.shared.prepare()
            artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            artifact = nil
        }
        let ctx = makeCompilationContext(
            inputs: inputs,
            stdlibLibraryPath: artifact,
            allowDefaultStdlibLibrary: false
        )
        if useArtifact {
            #expect(ctx.options.stdlibLibraryPath == artifact)
            #expect(!ctx.options.includeStdlib)
        } else {
            #expect(ctx.options.stdlibLibraryPath == nil)
            #expect(ctx.options.includeStdlib)
        }
        return ctx
    }

    private func context(source: String, useArtifact: Bool) throws -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = try context(inputs: [path], useArtifact: useArtifact)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [false, true])
    func companionPropertyDirectImportsResolve(useArtifact: Bool) throws {
        let source = try repositoryFileSource("Scripts/diff_cases/companion_property_direct_import.kt")
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func companionPropertyImportsResolveWithUnrelatedImplicitReceivers(useArtifact: Bool) throws {
        let source = """
        import kotlin.Int.Companion.MAX_VALUE
        import kotlin.Long.Companion.MIN_VALUE as longMin
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.ZERO as zeroDuration

        fun String.maximum(): Int = MAX_VALUE
        class Reader {
            fun minimum(): Long = longMin
            fun zero(): Duration = with("receiver") { zeroDuration }
        }
        fun shadow(): Int { val MAX_VALUE = 7; return MAX_VALUE }
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "", "import library.*", "import library.answer", "import library.answer as renamed",
        "import library.ordinary", "import library.ordinary as renamed",
    ])
    func extensionPropertyImportsStillRequireReceiver(importDirective: String) throws {
        let declarations = """
        package library
        object Singleton
        val Singleton.answer: Int get() = 42
        val Int.ordinary: Int get() = this
        """
        let name = importDirective.contains("as renamed") ? "renamed"
            : importDirective.contains("ordinary") ? "ordinary" : "answer"
        let usage = """
        package app
        \(importDirective)
        fun read(): Int = \(name)
        """
        try withTemporaryFiles(contents: [declarations, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0022")
        }
    }

    @Test(arguments: [false, true])
    func unusedUnresolvedExplicitImportsAreDiagnosed(useArtifact: Bool) throws {
        let source = try repositoryFileSource(
            "docs/fixtures/js_annotations/diagnostics/collection_imports.kt"
        )
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)

        let unresolvedImports = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT"
        }
        #expect(DiagnosticRegistry.lookup("KSWIFTK-SEMA-UNRESOLVED-IMPORT")?.pass == "SEMA")
        #expect(unresolvedImports.count == 3, "Expected all three unused imports to be rejected: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func unresolvedMemberImportIsDiagnosedEvenWhenMemberIsUsed(useArtifact: Bool) throws {
        let source = """
        @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)
        import kotlin.js.collections.asJsMapView
        fun use(values: MutableMap<String, Int>) {
            values.asJsMapView()
        }
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)

        let importErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message == "Unresolved import path."
        }
        #expect(importErrors.count == 1, "Expected the unused-as-import error while the member call still resolves: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func nestedMemberAndExtensionImportsResolve(useArtifact: Bool) throws {
        let source = """
        import kotlin.collections.Map.Entry
        import kotlin.collections.Map.Entry as MapEntry
        import kotlin.ranges.isEmpty

        fun identity(entry: Entry<String, Int>): Entry<String, Int> = entry
        fun identityAlias(entry: MapEntry<String, Int>): MapEntry<String, Int> = entry
        fun isEmpty(range: IntRange): Boolean = range.isEmpty()
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = try context(inputs: paths, useArtifact: useArtifact)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func javaLangIllegalArgumentExceptionImportResolvesAsKotlinType(useArtifact: Bool) throws {
        let source = """
        import java.lang.IllegalArgumentException
        import java.lang.IllegalArgumentException as JavaIllegalArgumentException

        fun fromImportedName(): IllegalArgumentException = JavaIllegalArgumentException("alias")
        fun kotlinFromJava(value: JavaIllegalArgumentException): kotlin.IllegalArgumentException = value
        fun javaFromKotlin(value: kotlin.IllegalArgumentException): JavaIllegalArgumentException = value
        fun withMessageAndCause(cause: Throwable): JavaIllegalArgumentException =
            JavaIllegalArgumentException("message", cause)
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let javaAlias = try #require(sema.symbols.lookup(
            fqName: ["java", "lang", "IllegalArgumentException"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.symbol(javaAlias)?.kind == .typeAlias)
    }

    @Test
    func wildcardImportFromObjectIsDiagnosed() throws {
        let source = """
        package probes
        import probes.Holder.*

        @AliasedAnn(1)
        class ViaStar

        object Holder {
            annotation class AliasedAnn(val v: Int)
        }
        """
        let ctx = try context(source: source, useArtifact: true)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0027" }
        #expect(diagnostics.count == 1, "Expected the object wildcard import to be rejected: \(ctx.diagnostics.diagnostics)")
        #expect(diagnostics.first?.message == "Cannot import on demand from object 'Holder'.")
    }

    @Test
    func explicitAndAliasedNestedObjectImportsResolve() throws {
        let source = """
        package probes
        import probes.Holder.AliasedAnn
        import probes.Holder.AliasedAnn as RenamedAnn

        @AliasedAnn(1)
        class ViaExplicit

        @RenamedAnn(2)
        class ViaAlias

        object Holder {
            annotation class AliasedAnn(val v: Int)
        }
        """
        let ctx = try context(source: source, useArtifact: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["import importfixture.library.*", "import importfixture.library"])
    func sourcePackageImportFallbackStillContributesMembers(importDirective: String) throws {
        let sources = [
            """
            package importfixture.library
            class Token
            fun token(): Token = Token()
            """,
            """
            package importfixture.app
            \(importDirective)
            fun use(): Token = token()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func samePackageOverloadDoesNotHideExplicitlyImportedFunction(useArtifact: Bool) throws {
        let sources = [
            """
            package imported
            fun choose(value: Any): String = "imported"
            """,
            """
            package repro
            fun min(first: Int, second: Int, third: Int): Int = first + second + third
            """,
            """
            package repro
            import kotlin.math.min
            import kotlin.math.min as min2
            import imported.choose
            fun minimum2(first: Int, second: Int): Int = min(first, second)
            fun minimum3(first: Int, second: Int, third: Int): Int = min(first, second, third)
            fun minimumAlias2(first: Int, second: Int): Int = min2(first, second)
            fun minimumQualified2(first: Int, second: Int): Int = kotlin.math.min(first, second)
            fun choose(value: String): String = "same-package"
            fun chooseResult(): String = choose("value")
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = try context(inputs: paths, useArtifact: useArtifact)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let twoArgumentCall = try #require(selectedCall(
                named: "min", inFunction: "minimum2", ast: ast, sema: sema, interner: ctx.interner
            ))
            let threeArgumentCall = try #require(selectedCall(
                named: "min", inFunction: "minimum3", ast: ast, sema: sema, interner: ctx.interner
            ))
            let aliasedCall = try #require(selectedCall(
                named: "min2", inFunction: "minimumAlias2", ast: ast, sema: sema, interner: ctx.interner
            ))
            let priorityCall = try #require(selectedCall(
                named: "choose", inFunction: "chooseResult", ast: ast, sema: sema, interner: ctx.interner
            ))

            #expect(twoArgumentCall.fqName == "kotlin.math.min")
            #expect(twoArgumentCall.arity == 2)
            #expect(threeArgumentCall.fqName == "repro.min")
            #expect(threeArgumentCall.arity == 3)
            #expect(aliasedCall.fqName == "kotlin.math.min")
            #expect(aliasedCall.arity == 2)
            #expect(priorityCall.fqName == "imported.choose")
        }
    }

    @Test
    func samePackageFunctionStillRequiresAnExplicitImport() throws {
        let source = """
        package repro
        fun min(first: Int, second: Int, third: Int): Int = first + second + third
        fun minimum2(first: Int, second: Int): Int = min(first, second)
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter { $0.severity == .error }
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "Expected the missing-import call to remain inapplicable: \(errors)")
        }
    }

    private func selectedCall(
        named calleeName: String,
        inFunction functionName: String,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> (fqName: String, arity: Int)? {
        let function = ast.sortedFiles
            .flatMap { file in
                file.topLevelDecls.compactMap { declID -> FunDecl? in
                    guard case let .funDecl(function) = ast.arena.decl(declID),
                          interner.resolve(function.name) == functionName else {
                        return nil
                    }
                    return function
                }
            }
            .first
        guard let function else { return nil }

        let bodyRange: SourceRange
        switch function.body {
        case .block(_, let range), .expr(_, let range):
            bodyRange = range
        case .unit:
            return nil
        }

        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let exprRange = ast.arena.exprRange(exprID), bodyRange.contains(exprRange),
                  case let .call(calleeID, _, _, _) = ast.arena.expr(exprID),
                  case let .nameRef(name, _) = ast.arena.expr(calleeID),
                  interner.resolve(name) == calleeName,
                  let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                  let symbol = sema.symbols.symbol(chosen),
                  let signature = sema.symbols.functionSignature(for: chosen) else {
                continue
            }
            return (
                symbol.fqName.map(interner.resolve).joined(separator: "."),
                signature.parameterTypes.count
            )
        }
        return nil
    }

    @Test(arguments: [false, true])
    func bundledJvmAnnotationsContinuationAndCoroutineIntrinsicsAreImportable(useArtifact: Bool) throws {
        let sources = [
            """
            @file:JvmName("KUU1851JvmMarkers")
            @file:JvmMultifileClass
            import kotlin.jvm.JvmName
            import kotlin.jvm.JvmMultifileClass
            import kotlin.jvm.JvmOverloads

            @JvmName("renamed")
            @JvmOverloads
            fun named(value: Int = 0): Int = value
            """,
            """
            import kotlin.jvm.JvmInline
            import kotlin.jvm.JvmStatic
            import kotlin.jvm.JvmField

            @JvmInline value class Wrapped(val value: Int)

            object Holder {
                @JvmStatic fun staticMethod() = Unit
                @JvmField val field = 1
            }
            """,
            """
            import kotlin.coroutines.Continuation
            import kotlinx.coroutines.intrinsics.startCoroutineCancellable

            fun start(block: suspend () -> Unit, completion: Continuation<Unit>) {
                block.startCoroutineCancellable(completion)
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = try context(inputs: paths, useArtifact: useArtifact)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func wildcardImportResolvesPrecompiledLibraryPackage() throws {
        let source = """
        import kotlin.ranges.*
        fun isEmpty(range: IntRange): Boolean = range.isEmpty()
        """
        let ctx = try context(source: source, useArtifact: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
