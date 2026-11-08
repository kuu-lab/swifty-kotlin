#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionConstructorArityTests {
    /// KUU-4448: the source-backed collection constructor shortcut used to
    /// fabricate the result type without overload resolution, so calls with
    /// mismatched arity or argument types compiled silently into empty
    /// collections. kotlinc rejects every one of these forms.
    @Test(arguments: [
        #"val a = HashMap<String, Int>("x", 1.5, true)"#,
        #"val a = ArrayList<Int>("x", "y")"#,
        #"val a = HashSet<Int>("x")"#,
        #"val a = LinkedHashSet<Int>("x")"#,
        #"val a = ArrayList<String>("x")"#,
        #"val a = HashMap<String, Int>(mapOf("a" to 1), "extra")"#,
    ])
    func invalidConstructorArgumentsAreRejected(declaration: String) throws {
        let ctx = makeContextFromSource("""
        fun main() {
            \(declaration)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error
        }, "Expected a compile error for `\(declaration)`: \(ctx.diagnostics.diagnostics)")
    }

    /// Every constructor form declared by the bundled collection classes must
    /// keep compiling and inferring through the shortcut path.
    @Test func validConstructorFormsStillCompile() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val a1 = ArrayList<Int>()
            val a2 = ArrayList<Int>(10)
            val a3 = ArrayList(listOf(1, 2, 3))
            val s1 = HashSet<Int>()
            val s2 = HashSet<Int>(16)
            val s3 = HashSet<Int>(16, 0.5f)
            val s4 = HashSet(listOf("a", "b"))
            val s5 = LinkedHashSet<Int>()
            val s6 = LinkedHashSet<Int>(4)
            val s7 = LinkedHashSet(listOf(7, 8))
            val m1 = HashMap<String, Int>()
            val m2 = HashMap<String, Int>(8)
            val m3 = HashMap<String, Int>(8, 0.5f)
            val m4 = HashMap(mapOf("a" to 1, "b" to 2))
            val m5 = LinkedHashMap<String, Int>()
            val m6 = LinkedHashMap<String, Int>(8)
            val m7 = LinkedHashMap<String, Int>(8, 0.5f)
            val m8 = LinkedHashMap(mapOf("b" to 2))
            val expectedA: ArrayList<String> = ArrayList()
            val expectedM: HashMap<Int, String> = HashMap()
            println("${a1.size}${a2.size}${a3.size}${s1.size}${s2.size}${s3.size}${s4.size}${s5.size}${s6.size}${s7.size}${m1.size}${m2.size}${m3.size}${m4.size}${m5.size}${m6.size}${m7.size}${m8.size}${expectedA.size}${expectedM.size}")
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
                "Expected no errors: \(ctx.diagnostics.diagnostics)")
    }

    /// KUU-4448: a user class that shares a collection constructor name keeps
    /// ordinary resolution — it must not acquire the synthetic collection
    /// result type (which would also let the lowering pass mistake it for the
    /// stdlib runtime bridge).
    @Test func userClassNamedArrayListKeepsOwnType() throws {
        let ctx = makeContextFromSource("""
        class ArrayList {
            val tag = "user"
        }

        fun make(): ArrayList = ArrayList()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty,
                "Expected no errors: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let make = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("make")]))
        let signature = try #require(sema.symbols.functionSignature(for: make))
        guard case let .classType(returnClass) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Expected make() to return the user ArrayList class type")
            return
        }
        #expect(sema.symbols.symbol(returnClass.classSymbol)?.fqName == [ctx.interner.intern("ArrayList")])
    }
}
#endif
