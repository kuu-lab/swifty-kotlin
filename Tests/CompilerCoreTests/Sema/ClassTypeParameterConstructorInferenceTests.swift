#if canImport(Testing)
@testable import CompilerCore
import Testing
import Foundation
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-3796: a constructor's class type parameters share symbols with the
/// class's lexical type parameters. Inside the class body, `P(key)` with
/// `key: T` must infer `P<T>` from the expected type — not `P<Any?>` from the
/// parameter's declared `Any?`.
@Suite
struct ClassTypeParameterConstructorInferenceTests {
    @Test(arguments: [true, false])
    func classTypeVariableArgumentToAnyParameterUsesExpectedType(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        class P<T>(val a: Any?) {
            fun f(key: T): P<T> {
                return P(key)
            }
        }
        """, fromSource: fromSource)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "P", in: ast, interner: ctx.interner))
        let type = try #require(sema.bindings.exprType(for: call))
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            Issue.record("Expected P class type")
            return
        }
        let ownerParameter = sema.types.allTypeParameterSymbols(for: classType.classSymbol).first
        guard case let .invariant(argument) = classType.args.first,
              case let .typeParam(parameter) = sema.types.kind(of: argument),
              parameter.symbol == ownerParameter
        else {
            Issue.record("Expected P<T>, got \(sema.types.renderType(type))")
            return
        }
    }

    @Test func multiParameterConstructorBindsAllClassParametersFromExpected() throws {
        let ctx = try makeTestContext("""
        class PersistentOrderedMap<K, V>(
            val firstKey: Any?,
            val lastKey: Any?,
            val payload: V
        ) {
            fun put(key: K, value: V): PersistentOrderedMap<K, V> {
                return PersistentOrderedMap(key, key, value)
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func boundedClassTypeVariableArgumentToAnyParameterUsesExpectedType() throws {
        let ctx = try makeTestContext("""
        class Q<T : Any>(val a: Any?) {
            fun f(key: T): Q<T> {
                return Q(key)
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func covariantConstructorParameterStillInfersFromExpected() throws {
        let ctx = try makeTestContext("""
        class CBox<out T>(val a: Any?) {
            fun f(key: @UnsafeVariance T): CBox<T> = CBox(key)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func declaredLocalTypeExpectationBindsConstructorParameters() throws {
        let ctx = try makeTestContext("""
        class DBox<T>(val a: Any?) {
            fun f(key: T): DBox<T> {
                val d: DBox<T> = DBox(key)
                return d
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func unrelatedExpectedTypeLeavesConstructorParameterUnbound() throws {
        // Kotlin cannot infer T when the expected type does not mention the
        // constructor's class, so the call must still be rejected.
        let ctx = try makeTestContext("""
        interface Holder
        class P<T>(val a: Any?) : Holder
        fun make(): Holder = P(1)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "P(1) without a usable expected type must not infer P<Any?>")
    }

    @Test func explicitConstructorTypeArgumentStillWins() throws {
        let ctx = try makeTestContext("""
        class P<T>(val a: Any?) {
            fun f(key: T): P<T> = P<T>(key)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// Keep focused inference tests cheap; end-to-end diff cases own source
    /// injection as well.
    private func makeTestContext(_ source: String, fromSource: Bool = false) throws -> CompilationContext {
        if fromSource { return makeContextFromSource(source) }
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib artifact must be available")
        let manifest = URL(fileURLWithPath: library).appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifest.path), "Shared stdlib artifact must have a manifest")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
