#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// KUU-3347: floating-point range values use an opaque runtime handle, but
    /// for-in must still honor a user-defined `ClosedRange<Double>.iterator()`.
    @Test
    func customClosedRangeDoubleIteratorDrivesForIn() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        operator fun ClosedRange<Double>.iterator() = object : Iterator<Double> {
            private var cur = start
            override fun hasNext() = cur <= endInclusive
            override fun next(): Double { val n = cur; cur += 0.1; return n }
        }

        fun main() {
            var sum = 0.0
            for (value in 0.0..1.0) sum += value
            println(sum)
        }
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let rangeLoopCallees = mainBody.compactMap { instruction -> String? in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
            let name = ctx.interner.resolve(callee)
            return name == "iterator" || name.hasPrefix("__kk_range_for_in_") ? name : nil
        }
        #expect(rangeLoopCallees.contains("iterator"), "Expected the user-defined iterator call, got: \(rangeLoopCallees)")
        #expect(
            !rangeLoopCallees.contains("__kk_range_for_in_iterator"),
            "Floating-point for-in must not use the integer range iterator: \(rangeLoopCallees)"
        )
    }

    /// KUU-3258: `x in r` on an untracked `ClosedFloatingPointRange`/`ClosedRange`
    /// receiver lowers into the bundled cross-type `contains` extension, whose
    /// body calls `contains(value.toFloat())` as an unqualified member call on
    /// the implicit extension receiver. That call must probe the runtime
    /// floating-point range box before falling through to itable dispatch, or
    /// the box (which registers no Kotlin itable) traps at lookup time.
    @Test
    func testImplicitRangeReceiverMemberCallProbesBeforeInterfaceDispatch() throws {
        let ctx = makeContextFromSource("""
        fun ClosedRange<Float>.crossContains(v: Double): Boolean = contains(v.toFloat())
        """)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let body = try #require(
            findAllKIRFunctions(in: module).first { function in
                function.body.contains { instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "__kk_floating_range_contains_or_null"
                }
            },
            "the unqualified `contains` call on the implicit range receiver must emit the runtime probe"
        ).body
        let dispatchIndex = try #require(body.firstIndex { instruction in
            guard case let .virtualCall(_, callee, _, _, _, _, _, dispatch) = instruction,
                  ctx.interner.resolve(callee) == "contains" else { return false }
            if case .itableDynamic = dispatch { return true }
            return false
        })
        #expect(body[..<dispatchIndex].contains { if case .jumpIfEqual = $0 { true } else { false } })
        #expect(body[(dispatchIndex + 1)...].contains { if case .label = $0 { true } else { false } })
    }

    /// KUU-3258: a user class that implements a stdlib range interface without
    /// overriding `contains`/`isEmpty` must register the interface's compiled
    /// default bodies (`kk_fn_*` imports) into its itable — the registration
    /// guard may only skip runtime-bridge and abstract members.
    @Test
    func testClosedRangeInterfaceDefaultsRegisterOnUserImplementation() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        class IntBounds(override val start: Int, override val endInclusive: Int) : ClosedRange<Int>
        fun make(): ClosedRange<Int> = IntBounds(1, 4)
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let registered = itableRegisteredMemberNames(in: module, sema: sema, interner: ctx.interner)
        #expect(registered.contains("contains"), "registered: \(registered)")
        #expect(registered.contains("isEmpty"), "registered: \(registered)")
    }

    /// Enum entries never run a constructor, so their itable is populated at
    /// box time — the same source-backed defaults must register there too.
    @Test
    func testClosedRangeInterfaceDefaultsRegisterOnEnumBox() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        enum class Color(override val start: Int, override val endInclusive: Int) : ClosedRange<Int> {
            R(1, 5), G(6, 9), B(10, 14);
        }
        fun make(): ClosedRange<Int> = Color.R
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let registered = itableRegisteredMemberNames(in: module, sema: sema, interner: ctx.interner)
        #expect(registered.contains("contains"), "registered: \(registered)")
        #expect(registered.contains("isEmpty"), "registered: \(registered)")
    }

    /// Names of member implementations registered through
    /// `kk_object_register_itable_method` anywhere in the module.
    private func itableRegisteredMemberNames(
        in module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        var names: Set<String> = []
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      interner.resolve(callee) == "kk_object_register_itable_method",
                      let fnExpr = arguments.last,
                      case let .symbolRef(symbol) = module.arena.expr(fnExpr),
                      let name = sema.symbols.symbol(symbol)?.name
                else { continue }
                names.insert(interner.resolve(name))
            }
        }
        return names
    }
}
#endif
