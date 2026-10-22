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
    func classCompanionMembersCanBeImportedThroughClassName(useArtifact: Bool) throws {
        let source = """
        import Foo.BAR
        import Foo.answer as companionAnswer

        class Foo {
            companion object {
                val BAR = 42
                fun answer(): Int = BAR
            }
        }

        fun importedProperty(): Int = BAR
        fun importedFunction(): Int = companionAnswer()
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = try context(inputs: [path], useArtifact: useArtifact)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")
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

    @Test(arguments: [false, true])
    func inheritedObjectMemberImportsResolve(useArtifact: Bool) throws {
        let source = """
        import C.inherited
        import C.fromInterface
        import C.genericFromSuper
        import C.overload
        import C.own
        import C.ownExtension
        import C.ext
        import C.g1
        import C.g2
        import C.fromClass
        import HidingC.inherited as hiddenInherited

        interface FromInterface<T> {
            fun <E> E.fromInterface(): E = this
            fun genericFromSuper(value: T): T = value
            fun genericFromSuper(): T? = null
        }
        open class Base {
            open fun inherited(): String = "OK"
            fun overload(value: Int): String = "int"
            fun overload(value: String): String = "string"
            val <E> E.fromClass: E get() = this
        }
        object C : Base(), FromInterface<String> {
            fun own(): String = "OK"
            fun Boolean.ownExtension(): Int = 3
            val Int.ext: Int get() = 6
            fun <E> g1(value: E): E = value
            val <E> E.g2: E get() = this
        }
        object HidingC : Base() {
            override fun inherited(): String = "hidden"
        }

        fun importedClassMember(): String = inherited()
        fun importedInterfaceExtension(): Int = 9.fromInterface()
        fun importedClassExtensionProperty(): String = "OK".fromClass
        fun importedOwnExtension(): Int = true.ownExtension()
        fun importedOwnExtensionProperty(): Int = 5.ext
        fun importedGenericExtensionFunction(): String = g1("OK")
        fun importedGenericExtensionProperty(): String = "OK".g2
        fun importedGenericMember(): String = genericFromSuper("OK")
        fun importedGenericDefault(): String? = genericFromSuper()
        fun importedIntOverload(): String = overload(1)
        fun importedStringOverload(): String = overload("OK")
        fun importedOwnMember(): String = own()
        fun importedAlias(): String = hiddenInherited()
        fun qualified(): String = C.inherited()
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let stdlibArtifact: String?
        if useArtifact {
            TestStdlibCache.shared.prepare()
            stdlibArtifact = CompilerOptions.defaultStdlibLibraryPath
        } else {
            stdlibArtifact = nil
        }
        let ctx = makeCompilationContext(
            inputs: [path],
            includeStdlib: false,
            stdlibLibraryPath: stdlibArtifact,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let objectC = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("C")]))
        let hidingC = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("HidingC")]))
        let importedCallNames: Set<String> = [
            "inherited", "fromInterface", "fromClass", "genericFromSuper", "overload", "own",
            "hiddenInherited", "ownExtension", "ext", "g1", "g2",
        ]
        let importedCalls = sema.bindings.callBindings.compactMap { expression, binding -> (String, SymbolID?)? in
            let sourceName: InternedString?
            switch ast.arena.expr(expression) {
            case let .call(callee, _, _, _):
                if case let .nameRef(name, _) = ast.arena.expr(callee) {
                    sourceName = name
                } else {
                    sourceName = nil
                }
            case let .memberCall(_, name, _, _, _), let .safeMemberCall(_, name, _, _, _):
                sourceName = name
            default:
                sourceName = nil
            }
            guard let sourceName,
                  let range = ast.arena.exprRange(expression),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { return nil }
            let nameText = ctx.interner.resolve(sourceName)
            guard importedCallNames.contains(nameText) else { return nil }
            return (nameText, binding.dispatchReceiverSymbol)
        }
        #expect(importedCalls.count == 14, "Unexpected imported calls: \(importedCalls)")
        #expect(importedCalls.allSatisfy { name, receiver in
            receiver == (name == "hiddenInherited" ? hidingC : objectC)
        }, "Imported calls must retain their singleton dispatch receiver: \(importedCalls)")
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

    /// KUU-2731: a star-imported non-callable property must not hide a
    /// same-named default-imported function in call syntax.
    @Test(arguments: [false, true])
    func starImportedPropertyDoesNotShadowDefaultImportedFunctionCall(useArtifact: Bool) throws {
        let owner = """
        package kk
        val emptyMap: Map<String, String> = mapOf()
        """
        let usage = """
        package kk.impl
        import kk.*
        class DM { var backing: Map<String, String> = emptyMap() }
        """
        try withTemporaryFiles(contents: [owner, usage]) { paths in
            let ctx = try context(inputs: paths, useArtifact: useArtifact)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[1], in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
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

    @Test(arguments: [false, true])
    func javaUtilNoSuchElementExceptionImportResolvesAsKotlinType(useArtifact: Bool) throws {
        let source = """
        import java.util.NoSuchElementException
        import java.util.NoSuchElementException as JavaNoSuchElementException

        fun fromImportedName(): NoSuchElementException = JavaNoSuchElementException("empty")
        fun kotlinFromJava(value: JavaNoSuchElementException): kotlin.NoSuchElementException = value
        fun javaFromKotlin(value: kotlin.NoSuchElementException): JavaNoSuchElementException = value
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let javaAlias = try #require(sema.symbols.lookup(
            fqName: ["java", "util", "NoSuchElementException"].map(ctx.interner.intern)
        ))
        #expect(sema.symbols.symbol(javaAlias)?.kind == .typeAlias)
    }

    @Test(arguments: [false, true])
    func unknownJavaUtilExceptionImportRemainsUnresolved(useArtifact: Bool) throws {
        let source = """
        import java.util.KUU2296UnknownException
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)
        let unresolvedImports = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT"
        }
        #expect(unresolvedImports.count == 1, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
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

    /// `useContents` is a real Kotlin/Native top-level extension that user code
    /// imports by name, even though the compiler handles the call through
    /// scope-function interception rather than a declaration: the import must
    /// still resolve (it used to report KSWIFTK-SEMA-UNRESOLVED-IMPORT) and the
    /// intercepted call must keep type-checking.
    @Test(arguments: [false, true])
    func cinteropUseContentsImportResolves(useArtifact: Bool) throws {
        let source = """
        import kotlinx.cinterop.CStructVar
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.useContents

        @ExperimentalForeignApi
        fun <T : CStructVar> expose(value: CValue<T>): T {
            return value.useContents { this }
        }
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func cinteropUseContentsAliasImportResolves(useArtifact: Bool) throws {
        let source = """
        import kotlinx.cinterop.useContents as contents

        fun unrelated(): Int = 1
        """
        let ctx = try context(source: source, useArtifact: useArtifact)
        try runSema(ctx)

        let unresolvedImports = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" }
        #expect(unresolvedImports.isEmpty, "Aliased useContents import must resolve: \(unresolvedImports)")
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
