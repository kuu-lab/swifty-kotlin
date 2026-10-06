#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for four default-argument / vararg lowering bugs whose
/// executable counterparts live in `Scripts/diff_cases/`
/// (`vararg_forward_spread`, `ctor_defaults_this_delegation`,
/// `default_function_typed_param`, `local_function_defaults`).
extension BuildKIRRegressionTests {
    /// The empty-vararg path used to hand the callee a bare `kk_array_new(0)`
    /// while a non-empty call passed `__kk_array_toList(...)`, so a vararg
    /// parameter was an Array or a List depending on the caller's arguments.
    @Test
    func emptyVarargArgumentIsListifiedLikeNonEmptyPacking() throws {
        let source = """
        fun count(vararg xs: Int) = xs.size
        fun probe(): Int = count()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("__kk_array_toList"), "Expected the empty vararg to be listified, got: \(callees)")
    }

    /// A function-typed parameter's default lambda must be wrapped into a
    /// function value (`kk_function_create_N`) inside the `$default` stub,
    /// otherwise `kk_function_invoke` sees a raw code pointer and yields null.
    @Test
    func functionTypedDefaultValueIsMaterializedInDefaultStub() throws {
        let source = """
        fun trailing(n: Int = 1, block: (Int) -> String = { "d$it" }) = block(n)
        fun probe(): String = trailing()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let stub = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "trailing$default"
        })
        let callees = extractCallees(from: stub.body, interner: ctx.interner)
        #expect(callees.contains("kk_function_create_1"), "Got: \(callees)")
    }

    /// Call sites of a local function with omitted arguments call
    /// `<name>$default`; before the fix no such stub was ever emitted.
    @Test
    func localFunctionDefaultsGenerateStubThatForwardsCaptures() throws {
        let source = """
        fun probe(): Int {
            val base = 100
            fun addBase(x: Int, extra: Int = 1): Int = base + x + extra
            return addBase(5)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let stub = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "addBase$default"
        })
        // capture(base) + x + extra + default mask
        #expect(stub.params.count == 4, "Got: \(stub.params.count)")
        let original = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "addBase"
        })
        #expect(original.params.count == 3, "Got: \(original.params.count)")

        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        #expect(extractCallees(from: body, interner: ctx.interner).contains("addBase$default"))
    }

    /// `this(...)` used to lower the delegation args positionally into a plain
    /// `<init>` call (3 args for a 4-slot constructor), reading garbage for the
    /// omitted defaults.
    @Test
    func secondaryConstructorThisDelegationRoutesThroughDefaultStub() throws {
        let source = """
        class Ctor(val a: Int, val b: String = "b$a") {
            constructor(s: String) : this(s.length)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let delegatesThroughStub = findAllKIRFunctions(in: module).contains { function in
            ctx.interner.resolve(function.name) == "Ctor"
                && extractCallees(from: function.body, interner: ctx.interner).contains("Ctor$default")
        }
        #expect(delegatesThroughStub, "Expected the secondary constructor to call Ctor$default")
    }

    @Test
    func superConstructorCallWithOmittedDefaultRoutesThroughDefaultStub() throws {
        let source = """
        open class Base(val p: Int, val q: String = "q$p")
        class Derived : Base(3)
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let delegatesThroughStub = findAllKIRFunctions(in: module).contains { function in
            ctx.interner.resolve(function.name) == "Derived"
                && extractCallees(from: function.body, interner: ctx.interner).contains("Base$default")
        }
        #expect(delegatesThroughStub, "Expected Derived's super call to use Base$default")
    }

    @Test(arguments: [
        "class Writer { fun write(value: Unit = run { args = Args(null) }) {} }; Writer().write()",
        "class Writer(value: Unit = run { args = Args(null) }); Writer()",
        "class Writer { constructor(value: Unit = kotlin.run { args = Args(null) }) {} }; Writer()",
    ])
    func localClassDefaultStubRestoresCapturedCell(_ declaration: String) throws {
        let source = """
        class Args(val x: String?)
        fun probe() {
            var args = Args("hello")
            \(declaration)
            println(args.x)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let stub = try #require(findAllKIRFunctions(in: module).first {
            let name = ctx.interner.resolve($0.name)
            return name == "write$default" || name == "Writer$default"
        })
        #expect(stub.params.count == 3, "Expected receiver, value, and mask parameters")
        let loads = stub.body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_array_get_inbounds"
            else {
                return nil
            }
            return result
        }
        #expect(loads.count == 1, "Expected the captured mutable cell to be restored from the receiver")
        let sema = try #require(ctx.sema)
        let cell = try #require(loads.first)
        #expect(module.arena.exprType(cell) == sema.types.anyType)
    }
}
#endif
