@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4070: `kotlin.reflect.full` is not a Kotlin default import — its
/// extensions must not resolve on member-style calls without an explicit
/// import. The `kotlin.reflect` shim surface (KSP-496) stays importless by
/// design; only the kotlin-reflect port package is gated.
@Suite
struct ReflectFullImportGatingTests {
    @Test func membersRequireReflectFullImport() throws {
        let sources = [
            // Each file uses one kotlin.reflect.full member without an
            // import; kotlinc reports an unresolved reference for all of
            // them.
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.isSubclassOf(String::class)",
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.isSuperclassOf(String::class)",
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.primaryConstructor",
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.starProjectedType",
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.createType()",
            "import kotlin.reflect.KClass\nfun f(k: KClass<*>) = k.findAnnotation<Annotation>()",
            // An aliased import exposes only the alias — the original name
            // stays unresolved.
            "import kotlin.reflect.KClass\nimport kotlin.reflect.full.isSubclassOf as checkSubclass\nfun f(k: KClass<*>) = k.isSubclassOf(String::class)",
        ]
        let ctx = makeContextFromSources(sources.enumerated().map { index, source in
            "package gated\(index)\n" + source
        }, allowDefaultStdlibLibrary: false)
        do { try runSema(ctx) } catch { }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let files = ctx.sourceManager.fileIDs().filter { ctx.sourceManager.origin(of: $0) == .user }
        #expect(files.count == sources.count)
        for (index, file) in files.enumerated() {
            #expect(
                errors.contains { $0.primaryRange?.start.file == file },
                "Expected a user-source diagnostic for: \(sources[index]); got \(errors)"
            )
        }
    }

    @Test func importedMembersResolve() throws {
        let ctx = makeContextFromSources([
            """
            package wildcard
            import kotlin.reflect.KClass
            import kotlin.reflect.full.*
            fun sub(k: KClass<*>) = k.isSubclassOf(String::class)
            fun sup(k: KClass<*>) = k.isSuperclassOf(String::class)
            fun ctor(k: KClass<*>) = k.primaryConstructor
            fun star(k: KClass<*>) = k.starProjectedType
            fun make(k: KClass<*>) = k.createType()
            """,
            """
            package exact
            import kotlin.reflect.KClass
            import kotlin.reflect.full.isSubclassOf
            fun sub(k: KClass<*>) = k.isSubclassOf(String::class)
            """,
            """
            package aliased
            import kotlin.reflect.KClass
            import kotlin.reflect.full.isSubclassOf as checkSubclass
            fun sub(k: KClass<*>) = k.checkSubclass(String::class)
            """,
        ], allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let reflectFullIsSubclassOf = Set(sema.symbols.lookupAll(fqName: [
            "kotlin", "reflect", "full", "isSubclassOf",
        ].map(ctx.interner.intern)))
        #expect(
            sema.bindings.callBindings.values.contains {
                reflectFullIsSubclassOf.contains($0.chosenCallee)
            },
            "Expected an imported call to bind kotlin.reflect.full.isSubclassOf"
        )
    }

    @Test func reflectShimMembersStayImportless() throws {
        // KSP-496: `kotlin.reflect` shim members are deliberately
        // member-like and remain callable without an import. Once the
        // reflect.full port is gated, an unqualified `cast`/`safeCast`
        // resolves unambiguously to the shim instead of reporting the
        // duplicate-candidate ambiguity from KUU-4070.
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KClass
        fun castValue(k: KClass<String>, v: Any?): String = k.cast(v)
        fun safeCastValue(k: KClass<String>, v: Any?): String? = k.safeCast(v)
        fun members(k: KClass<*>) = k.memberProperties
        fun declMembers(k: KClass<*>) = k.declaredMemberFunctions
        """, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        for name in ["cast", "safeCast"] {
            let shimSymbols = Set(sema.symbols.lookupAll(fqName: [
                "kotlin", "reflect", name,
            ].map(ctx.interner.intern)))
            #expect(
                sema.bindings.callBindings.values.contains {
                    shimSymbols.contains($0.chosenCallee)
                },
                "Expected `\(name)` to bind the kotlin.reflect shim without an import"
            )
        }
    }
}
