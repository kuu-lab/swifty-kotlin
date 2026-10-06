#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LateinitKIRTests {
    @Test func testLateinitReadEmitsGetOrThrowCall() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun read(): String = name
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "lateinit read should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_lateinit_get_or_throw"),
                      "Expected kk_lateinit_get_or_throw in read body, got: \(callees)")
    }

    @Test func testLateinitIsInitializedEmitsRuntimeCheck() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun ready(): Boolean = ::name.isInitialized
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "lateinit isInitialized should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "ready", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(callees.contains("kk_lateinit_is_initialized"),
                      "Expected kk_lateinit_is_initialized in ready body, got: \(callees)")
    }

    /// `c::name.isInitialized` on a bound receiver inside the declaring class
    /// must read the backing field directly like `this::name`/`::name` do —
    /// materializing the KProperty0 wrapper instead would invoke the stdlib
    /// `isInitialized` stub (which throws) and, for String properties, a
    /// dangling bridge callee that failed to link (KUU-1391).
    @Test func testBoundReceiverLateinitIsInitializedEmitsRuntimeCheck() throws {
        let source = """
        class C {
            lateinit var name: String
            fun probe(other: C): Boolean = other::name.isInitialized
        }
        lateinit var top: String
        fun main() {
            println(::top.isInitialized)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "bound lateinit isInitialized should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let probeCallees = extractCallees(
            from: try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner),
            interner: ctx.interner
        )
        #expect(probeCallees.contains("kk_lateinit_is_initialized"),
                "Expected kk_lateinit_is_initialized in probe body, got: \(probeCallees)")
        let mainCallees = extractCallees(
            from: try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner),
            interner: ctx.interner
        )
        #expect(mainCallees.contains("kk_lateinit_is_initialized"),
                "Expected kk_lateinit_is_initialized in main body, got: \(mainCallees)")
    }

    /// `c::name.isInitialized` outside the declaring class has no access to
    /// the private backing field — kotlinc rejects it, so SEMA must too.
    @Test func testBoundReceiverLateinitIsInitializedRejectsForeignScope() throws {
        let source = """
        class C { lateinit var name: String }
        fun main() {
            val c = C()
            println(c::name.isInitialized)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-LATEINIT"
                    && diagnostic.message.contains("not accessible")
            },
            "c::name.isInitialized outside C should reject: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    /// `C::name.isInitialized` is an unbound KProperty1 reference; kotlinc
    /// reports `isInitialized` as unresolved (it exists only on KProperty0),
    /// so SEMA must not accept it through the special-case either.
    @Test func testUnboundLateinitIsInitializedIsRejected() throws {
        let source = """
        class C { lateinit var name: String }
        fun check(): Boolean = C::name.isInitialized
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.hasError,
                "unbound C::name.isInitialized should be rejected: \(ctx.diagnostics.diagnostics.map { $0.message })")
    }

    @Test func testKProperty0IsInitializedRejectsValueReceiver() throws {
        let source = """
        import kotlin.reflect.KProperty0

        var value: Int = 7

        fun invalid(property: KProperty0<*>): Boolean = property.isInitialized
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.contains { diagnostic in
                diagnostic.code == "KSWIFTK-SEMA-LATEINIT"
                    && diagnostic.message.contains("property literals")
            },
            "KProperty0.isInitialized should reject value receivers: \(ctx.diagnostics.diagnostics.map { $0.message })"
        )
    }

    /// A lateinit read must leave `thrownResult` unset so the exception takes
    /// the ordinary propagation path; a private thrown slot nobody inspects
    /// turned uncaught reads into a silent `null`.
    @Test func testLateinitReadPropagatesThrowThroughCaller() throws {
        let source = """
        class Box {
            lateinit var name: String
            fun read(): String = name
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "read", in: module, interner: ctx.interner)
        let getOrThrow = body.compactMap { instruction -> KIRExprID?? in
            guard case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_lateinit_get_or_throw",
                  canThrow
            else { return nil }
            return .some(thrownResult)
        }
        #expect(getOrThrow.count == 1, "Expected one kk_lateinit_get_or_throw call: \(body)")
        #expect(getOrThrow.allSatisfy { $0 == nil },
                "kk_lateinit_get_or_throw must not capture its exception in a thrownResult slot")
    }

    /// The null sentinel is seeded at constructor entry, before the superclass
    /// constructor runs, so an assignment made by a virtual call from a
    /// superclass `init` block survives the subclass's own initialization.
    @Test func testLateinitSentinelStorePrecedesSuperConstructorCall() throws {
        let source = """
        abstract class Base {
            init { setup() }
            abstract fun setup()
        }
        class Derived : Base() {
            lateinit var s: String
            override fun setup() { s = "ready" }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!(ctx.diagnostics.hasError), "\(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "Derived", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        let superCallIndex = try #require(callees.firstIndex(of: "<init>"), "No super call in \(callees)")
        let fieldStoreIndices = callees.indices.filter { callees[$0] == "kk_array_set" }
        #expect(fieldStoreIndices.count == 1, "Expected exactly one sentinel store: \(callees)")
        #expect(fieldStoreIndices.allSatisfy { $0 < superCallIndex },
                "Sentinel store must precede the super constructor call: \(callees)")
    }

    /// Singleton storage is a zero-initialized global, so the lazy initializer
    /// must seed the null sentinel for a lateinit member.
    @Test func testObjectAndCompanionLazyInitSeedLateinitSentinel() throws {
        let source = """
        object Cfg {
            lateinit var name: String
        }
        class Host {
            companion object {
                lateinit var label: String
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!(ctx.diagnostics.hasError), "\(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let lazyInits = findAllKIRFunctions(in: module).filter { function in
            let name = ctx.interner.resolve(function.name)
            return name.hasPrefix("__object_lazy_init_") || name.hasPrefix("__companion_lazy_init_")
        }
        #expect(lazyInits.count == 2, "Expected object and companion lazy initializers")
        for function in lazyInits {
            let seedsNull = function.body.contains { instruction in
                if case .constValue(_, .null) = instruction { return true }
                return false
            }
            #expect(seedsNull, "\(ctx.interner.resolve(function.name)) must seed the lateinit sentinel")
        }
    }

    /// Object-literal members carry the lateinit flag, so reads are wrapped
    /// and `::p.isInitialized` type-checks.
    @Test func testObjectLiteralLateinitMemberIsRecognized() throws {
        let source = """
        interface Probe {
            fun ready(): Boolean
            fun read(): String
        }
        fun make(): Probe = object : Probe {
            lateinit var v: String
            override fun ready() = this::v.isInitialized
            override fun read() = v
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!(ctx.diagnostics.hasError), "\(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        // `Probe.read` is also a (bodiless) KIR function; pick the override.
        let readCallees = findAllKIRFunctions(in: module)
            .filter { ctx.interner.resolve($0.name) == "read" }
            .flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
        #expect(readCallees.contains("kk_lateinit_get_or_throw"), "\(readCallees)")
        let makeCallees = extractCallees(
            from: try findKIRFunctionBody(named: "make", in: module, interner: ctx.interner),
            interner: ctx.interner
        )
        #expect(makeCallees.contains("kk_array_set"), "Object literal must seed the sentinel: \(makeCallees)")
    }
}
#endif
