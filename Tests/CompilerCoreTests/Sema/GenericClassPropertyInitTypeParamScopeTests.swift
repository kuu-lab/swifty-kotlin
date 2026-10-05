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
            let receiver = try #require(function.receiver)
            #expect(sema.types.nullability(of: receiver) == .nullable)
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

    private func contextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func nullableClassTypeArgumentPreservesPropertyType() throws {
        let ctx = contextWithoutStdlib("""
        fun <X> makeIt(x: X): X = x
        class P<T : Any> {
            private val instance = makeIt<T?>(null)
            fun f(t: T) = makeIt<T>(t)
            fun nullable(t: T?) = makeIt<T?>(t)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("P")]))
        let parameter = try #require(sema.types.nominalTypeParameterSymbols(for: owner).first)
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("P"), ctx.interner.intern("instance"),
        ]))
        let propertyType = try #require(sema.symbols.propertyType(for: property))
        #expect(sema.types.kind(of: propertyType) == .typeParam(TypeParamType(
            symbol: parameter, nullability: .nullable
        )))
    }

    @Test func unresolvedCalleeDoesNotLoseNullableClassTypeParameterScope() {
        let ctx = contextWithoutStdlib("""
        class P<T : Any> {
            private val instance = atomic<T?>(null)
        }
        """)
        try? runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0025" }, "\(errors)")
        #expect(errors.allSatisfy { $0.primaryRange?.start.file != nil })
    }

    @Test(arguments: [
        "makeIt<Missing?>(null)",
        "factory.makeIt<Missing?>(null)",
        "optional?.makeIt<Missing?>(null)",
        "makeIt<Box<Missing?>>(null)",
        "makeIt<Box<out Missing?>>(null)",
        "makeIt<Box<in Missing?>>(null)",
        "makeIt<() -> Missing?>(null)",
        "makeIt<Missing.() -> Int>(null)",
        "makeIt<Missing?.() -> Int>(null)",
        "makeIt<(Missing?) -> Int>(null)",
        "atomic<Missing?>(null)",
    ])
    func unresolvedTypeArgumentHasInitializerSourceRange(_ initializer: String) throws {
        let source = """
        fun <X> makeIt(x: X): X = x
        class Box<T>
        class Factory {
            fun <X> makeIt(x: X): X = x
        }
        class P<T : Any>(val factory: Factory, val optional: Factory?) {
            private val instance = \(initializer)
        }
        """
        let ctx = contextWithoutStdlib(source)
        try? runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(diagnostics.count == 1, "\(ctx.diagnostics.diagnostics)")
        let diagnostic = try #require(diagnostics.first)
        #expect(diagnostic.message == "Unresolved type 'Missing'.")
        let range = try #require(diagnostic.primaryRange)
        #expect(range.start.file != .invalid)
        #expect(!ctx.sourceManager.path(of: range.start.file).isEmpty)
        #expect(ctx.sourceManager.lineColumn(of: range.start).line == 7)
        #expect(String(decoding: Array(source.utf8)[range.start.offset ..< range.end.offset], as: UTF8.self) == initializer)
    }

    @Test func repeatedUnresolvedTypeArgumentsKeepDistinctSourceRanges() throws {
        let ctx = contextWithoutStdlib("""
        fun <X> makeIt(x: X): X = x
        class P<T : Any> {
            private val first = makeIt<Missing?>(null)
            private val second = makeIt<Missing?>(null)
        }
        """)
        try? runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(diagnostics.count == 2, "\(ctx.diagnostics.diagnostics)")
        let ranges = try diagnostics.map { try #require($0.primaryRange) }
        #expect(Set(ranges).count == 2)
        #expect(Set(ranges.map { ctx.sourceManager.lineColumn(of: $0.start).line }) == [3, 4])
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
