#if canImport(Testing)
import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct LocalNominalGenericMemberMethodTypeParameterTests {
    private func memberFunctionSymbol(named name: String, in ctx: CompilationContext) throws -> SymbolID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for expression in ast.arena.exprs {
            guard case let .objectLiteral(_, declID?, _) = expression,
                  case let .objectDecl(objectDecl)? = ast.arena.decl(declID)
            else {
                continue
            }
            for memberDeclID in objectDecl.memberFunctions {
                guard case let .funDecl(functionDecl)? = ast.arena.decl(memberDeclID),
                      ctx.interner.resolve(functionDecl.name) == name
                else {
                    continue
                }
                return try #require(sema.bindings.declSymbol(for: memberDeclID))
            }
        }
        return try #require(nil as SymbolID?, "Expected anonymous object member function '\(name)'")
    }

    @Test(arguments: [false, true])
    func resolvesAnonymousObjectGenericMemberMethods(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        fun <T> test(): String {
            val x = object {
                fun <S> foo(value: S): S {
                    val copy: S = value
                    return copy
                }
                fun <S : CharSequence> anonymousBounded(value: S): S = value
                inline fun <reified S> matchesReified(value: Any): Boolean = value is S
            }
            return if (x.matchesReified<String>(x.anonymousBounded<String>(x.foo("OK")))) "OK" else "FAIL"
        }
        fun box() = test<Int>()
        """, fromSource: fromSource)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let sema = try #require(ctx.sema)
        let bounded = try #require(sema.symbols.functionSignature(
            for: memberFunctionSymbol(named: "anonymousBounded", in: ctx)
        ))
        let boundedTypeParameter = try #require(bounded.typeParameterSymbols.first)
        #expect(sema.symbols.typeParameterUpperBounds(for: boundedTypeParameter).count == 1)

        let reified = try #require(sema.symbols.functionSignature(
            for: memberFunctionSymbol(named: "matchesReified", in: ctx)
        ))
        #expect(reified.reifiedTypeParameterIndices == Set([0]))
        let reifiedTypeParameter = try #require(reified.typeParameterSymbols.first)
        #expect(sema.symbols.symbol(reifiedTypeParameter)?.flags.contains(.reifiedTypeParameter) == true)
    }

    /// KUU-3867: members whose types are only inferred (`val stored = v`,
    /// `fun get() = stored`) may still resolve to a captured type parameter
    /// once the body refines them. The object keeps every lexical type
    /// parameter as its own type arguments so these members substitute
    /// through them exactly like a member spelling the parameter does.
    @Test(arguments: [false, true])
    func preservesInferredMembersBoundToCapturedTypeParameters(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        private class Box {
            private fun <T : Any> make(v: T) = object {
                val stored = v
                fun get() = stored
            }
            fun use(): Int = make(6).get()
        }
        fun box(): Int = Box().use()
        """, fromSource: fromSource)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// KUU-3867: a member spelling a captured parameter (`makeWindow(): List<T>`
    /// on a `object : It<R>` nested in `windowed<T, R>`) must keep the whole
    /// class prefix — the receiver-owner constraints bind it positionally to
    /// the object type's argument list — while members spelling none drop it.
    @Test(arguments: [false, true])
    func preservesNestedObjectsSpellingCapturedTypeParameters(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        interface It<T> { fun hasNext(): Boolean; fun next(): T }
        interface Seq<T> { fun iterator(): It<T> }
        fun <T, R> Seq<T>.windowed(transform: (List<T>) -> R): Seq<R> {
            val source = this
            return object : Seq<R> {
                override fun iterator(): It<R> = object : It<R> {
                    val sourceIterator = source.iterator()
                    fun makeWindow(): List<T> = mutableListOf()
                    fun fill() {
                        while (sourceIterator.hasNext()) { }
                    }
                    fun compute() {
                        if (sourceIterator.hasNext()) { fill() }
                        transform(makeWindow())
                    }
                    override fun hasNext(): Boolean { compute(); return true }
                    override fun next(): R = transform(mutableListOf())
                }
            }
        }
        """, fromSource: fromSource)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func resolvesLocalClassGenericMemberMethods(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        fun box(): String {
            class Local {
                fun <S : CharSequence> identity(value: S): S {
                    val copy: S = value
                    return copy
                }
            }
            val local = Local()
            val inferred: String = local.identity("OK")
            return local.identity<String>(inferred)
        }
        """, fromSource: fromSource)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true])
    func rejectsExplicitTypeArgumentOutsideLocalMethodBound(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        fun invalid() {
            class Local {
                fun <S : CharSequence> bounded(value: S): S = value
            }
            Local().bounded<Int>(1)
        }
        """, fromSource: fromSource)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "An Int argument must not satisfy the CharSequence bound")
    }

    /// The shared stdlib cache covers artifact mode; `fromSource` exercises the bundled source path.
    private func makeTestContext(_ source: String, fromSource: Bool) throws -> CompilationContext {
        if fromSource {
            return makeContextFromSource(source)
        }
        TestStdlibCache.shared.prepare()
        let library = try #require(
            CompilerOptions.defaultStdlibLibraryPath,
            "Shared stdlib artifact must be available"
        )
        let manifest = URL(fileURLWithPath: library).appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifest.path))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
