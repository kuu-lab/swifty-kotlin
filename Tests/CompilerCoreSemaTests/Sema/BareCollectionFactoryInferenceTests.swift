#if canImport(Testing)
@testable import CompilerCore
import Testing
import Foundation
import TestStdlibCache
@testable import CompilerTestSupport

/// KUU-4002: kotlinc rejects a bare generic collection factory when neither
/// its call arguments nor the expected type supply a concrete type argument
/// ("cannot infer type for type parameter 'T'"). Star projections and `Any?`
/// are not evidence, but call-argument positions may defer the diagnostic
/// until the enclosing call's chosen parameter is known — `this(emptyList())`,
/// `xs.addAll(emptyList())`, and `list + emptyList()` still resolve.
///
/// Each test compiles the bundled stdlib from source once, so the cases are
/// grouped into a few source units instead of one compilation per case.
@Suite
struct BareCollectionFactoryInferenceTests {
    /// Lines marked `// REJECT` must each produce KSWIFTK-SEMA-INFER; the rest
    /// must not produce any error.
    @Test func bareFactoriesAndWeakContextsAreRejected() throws {
        let ctx = try makeTestContext("""
        fun sizeOf(c: Collection<*>) = c.size
        fun take(x: Any?) = 0
        fun <T> add(c: Collection<T>) = 0
        fun test(x: List<Int>) {
            val v1 = listOf()            // REJECT
            val v2 = emptyList()         // REJECT
            val v3 = setOf()             // REJECT
            val v4 = mapOf()             // REJECT
            val v5 = mutableListOf()     // REJECT
            val v6 = emptySet()          // REJECT
            val v7 = emptyMap()          // REJECT
            val v8 = mutableSetOf()      // REJECT
            val v9 = mutableMapOf()      // REJECT
            val v10 = arrayListOf()      // REJECT
            val v11 = hashSetOf()        // REJECT
            val v12 = hashMapOf()        // REJECT
            val v13 = emptyArray()       // REJECT
            sizeOf(listOf())             // REJECT
            sizeOf(emptyList())          // REJECT
            val star: List<*> = listOf() // REJECT
            listOf().size                // REJECT
            emptyList().firstOrNull()    // REJECT
            take(listOf())               // REJECT
            println(listOf())            // REJECT
            println(emptyList())         // REJECT
            add(emptyList())             // REJECT
            x == emptyList()             // REJECT
            1 in emptyList()             // REJECT
            run { println(listOf()) }    // REJECT
            listOf().let { println(it) } // REJECT
            Pair(listOf(), 1)            // REJECT
        }
        """, fromSource: true)
        try runSema(ctx)
        let inferErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-INFER"
        }
        #expect(inferErrors.count == 27, "expected one inference diagnostic per case, got: \(inferErrors)")
    }

    @Test func factoriesWithConcreteEvidenceAreAccepted() throws {
        let ctx = try makeTestContext("""
        fun ret(): List<Int> = emptyList()
        fun g(x: List<Int> = emptyList()) = x.size
        fun f(x: List<Int>) = "l"
        fun f(x: Set<Int>) = "s"
        fun take(l: List<Int>) = l.size
        class C<E>(val items: List<E>) {
            constructor() : this(emptyList())
        }
        class D<E> { fun make(): List<E> = emptyList() }
        fun test(x: List<Int>, xs: MutableList<Int>, y: List<Int>?) {
            val a: List<Int> = listOf()
            val b: List<Int> = emptyList()
            val c: Collection<Int> = emptyList()
            val s: Set<Int> = setOf()
            val m: Map<String, Int> = mapOf()
            val ml: MutableList<Int> = mutableListOf()
            val ms: MutableSet<Int> = mutableSetOf()
            val mm: MutableMap<String, Int> = mutableMapOf()
            val hm: HashMap<String, Int> = hashMapOf()
            val n: List<Nothing> = emptyList()
            val arr: Array<String> = emptyArray()
            val t1 = listOf<Int>()
            val t2 = emptyList<Int>()
            val nested: List<List<Int>> = listOf(listOf())
            val nested2: List<List<Int>> = listOf(emptyList())
            val nested3: Map<String, List<Int>> = mapOf("a" to emptyList())
            ret()
            g()
            take(emptyList())
            f(emptyList())
            C<Int>()
            D<Int>().make()
            xs.addAll(emptyList())
            x + emptyList()
            x + listOf()
            val mmm = mutableMapOf<String, List<Int>>()
            mmm["k"] = emptyList()
            y ?: emptyList()
        }
        """, fromSource: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// The prebuilt-artifact path keeps its existing resolution behavior;
    /// only the source-backed interception reports the new diagnostic.
    @Test func factoriesWithEvidenceAreAcceptedFromArtifact() throws {
        let ctx = try makeTestContext("""
        fun main() {
            val a: List<Int> = listOf()
            val nested: List<List<Int>> = listOf(listOf())
            val t = listOf<Int>()
            println("${a.size} ${nested.size} ${t.size}")
        }
        """, fromSource: false)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    private func makeTestContext(_ source: String, fromSource: Bool) throws -> CompilationContext {
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
