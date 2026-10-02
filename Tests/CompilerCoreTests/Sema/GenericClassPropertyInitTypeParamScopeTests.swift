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
