#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression: an unannotated member property's initializer is type-checked in
/// the class member scope, which used to omit the class's own type parameters.
/// Explicit type arguments such as `mutableListOf<T>()` then resolved to an
/// error type that poisoned every member using the property.
@Suite
struct GenericClassPropertyInitTypeParamScopeTests {
    @Test func nullableReceiverFunctionPropertyWithExplicitClassTypeArgument() throws {
        try withTemporaryFile(contents: """
        fun <X> makeIt(x: X): X = x
        class P<T : Any> {
            private val instance = makeIt<T?.() -> Int>({ 1 })
            fun read(value: T?): Int = instance(value)
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let property = try #require(memberProperty(named: "instance", ofClass: "P", in: ast, interner: ctx.interner))
            let initializer = try #require(property.initializer)
            let type = try #require(sema.bindings.exprType(for: initializer))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("Expected a function type, not Boolean")
                return
            }
            #expect(function.receiver != nil)
            #expect(function.returnType == sema.types.intType)
        }
    }

    @Test func unresolvedNullableReceiverIsDiagnosedAsAType() throws {
        try withTemporaryFile(contents: """
        fun <X> makeIt(x: X): X = x
        val instance = makeIt<Missing?.() -> Int>(null)
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0025" && $0.message.contains("Missing")
            })
            #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" })
        }
    }

    private func errorDiagnostics(_ source: String) -> [String] {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
    }

    @Test func listPropertyWithExplicitClassTypeArgument() {
        let errors = errorDiagnostics("""
        class Stack<T> {
            private val items = mutableListOf<T>()
            fun push(x: T) { items.add(x) }
            fun pop(): T = items.removeAt(items.size - 1)
            fun peek(): T? = items.lastOrNull()
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func hashMapPropertyWithTwoClassTypeArguments() {
        let errors = errorDiagnostics("""
        class Cache<K, V> {
            private val cache = HashMap<K, V>()
            fun put(k: K, v: V) { cache[k] = v }
            fun get(k: K): V? = cache[k]
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func nestedGenericPropertyInitializer() {
        let errors = errorDiagnostics("""
        class Nested<T> {
            private val xs = mutableListOf<List<T>>()
            fun add(l: List<T>) { xs.add(l) }
            fun first(): List<T> = xs.removeAt(0)
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func abstractRepoMapPropertyWithLookupByKey() {
        let errors = errorDiagnostics("""
        abstract class Repo<T, ID> {
            protected val store = mutableMapOf<ID, T>()
            abstract fun idOf(t: T): ID
            fun save(t: T) { store[idOf(t)] = t }
            fun find(id: ID): T? = store[id]
        }
        """)
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
