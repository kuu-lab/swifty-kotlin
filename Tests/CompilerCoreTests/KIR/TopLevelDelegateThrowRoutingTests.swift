#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1274: `rewriteDelegateAccesses` injects the synthesized `get`/`set`
/// accessor calls AFTER try bodies were already throw-wrapped by
/// `appendThrowAwareInstructions`, so accessor calls inside a finally-guard
/// region used to keep `thrownResult: nil` — the thrown value propagated out
/// of the function and a top-level `Delegates.notNull()` read wrapped in
/// try/catch died with KSWIFTK-LINK-0003 instead of reaching the catch.
/// The rewrite now recovers the region's exception slot / type slot /
/// dispatch label and wires the accessor call the same way.
@Suite
struct TopLevelDelegateThrowRoutingTests {
    @Test func testTopLevelDelegateGetInsideTryRoutesThrownToCatchDispatch() throws {
        let source = """
        import kotlin.properties.Delegates
        var late: String by Delegates.notNull()
        fun main() {
            try {
                println(late)
            } catch (e: IllegalStateException) {
                println("caught")
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
        #expect(!(ctx.diagnostics.hasError), "top-level delegated read in try should compile: \(diagnosticMessages)")

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        var inGuard = false
        var accessorThrownResult: KIRExprID?
        var routedToDispatch = false
        for instruction in mainBody {
            switch instruction {
            case .beginFinallyGuard:
                inGuard = true
            case .endFinallyGuard:
                inGuard = false
            case let .call(_, callee, _, _, _, thrownResult, _, _) where inGuard:
                if ctx.interner.resolve(callee) == "get" {
                    accessorThrownResult = thrownResult
                }
            case let .jumpIfNotNull(value, _) where inGuard:
                if value == accessorThrownResult {
                    routedToDispatch = true
                }
            default:
                break
            }
        }
        let slot = try #require(
            accessorThrownResult,
            "expected the synthesized `get` accessor call to carry a thrownResult inside the try region"
        )
        #expect(
            routedToDispatch,
            "the accessor call must be followed by jumpIfNotNull(\(slot)) routing to the catch dispatch"
        )
    }

    @Test func testTopLevelDelegateSetInsideTryRoutesThrownToCatchDispatch() throws {
        let source = """
        import kotlin.properties.Delegates
        var accepted: Int by Delegates.vetoable(0) { _, _, new -> new >= 0 }
        fun main() {
            try {
                accepted = -1
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let diagnosticMessages = ctx.diagnostics.diagnostics.map(\.message)
        #expect(!(ctx.diagnostics.hasError), "top-level delegated write in try should compile: \(diagnosticMessages)")

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        var inGuard = false
        var accessorThrownResult: KIRExprID?
        var routedToDispatch = false
        for instruction in mainBody {
            switch instruction {
            case .beginFinallyGuard:
                inGuard = true
            case .endFinallyGuard:
                inGuard = false
            case let .call(_, callee, _, _, _, thrownResult, _, _) where inGuard:
                if ctx.interner.resolve(callee) == "set" {
                    accessorThrownResult = thrownResult
                }
            case let .jumpIfNotNull(value, _) where inGuard:
                if value == accessorThrownResult {
                    routedToDispatch = true
                }
            default:
                break
            }
        }
        let slot = try #require(
            accessorThrownResult,
            "expected the synthesized `set` accessor call to carry a thrownResult inside the try region"
        )
        #expect(
            routedToDispatch,
            "the accessor call must be followed by jumpIfNotNull(\(slot)) routing to the catch dispatch"
        )
    }

    /// Fallback path: the delegated access is the only throwing call in the
    /// region, so no sibling `jumpIfNotNull` exposes the routing — the slots
    /// are recovered from the init block emitted before the guard and the
    /// dispatch label from the first label after the region's end marker.
    @Test func testTopLevelDelegateGetAsOnlyRegionCallStillRoutesThrown() throws {
        let source = """
        import kotlin.properties.Delegates
        var late: String by Delegates.notNull()
        fun main() {
            try {
                val x = late
            } catch (e: IllegalStateException) {
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

        var inGuard = false
        var accessorThrownResult: KIRExprID?
        var routedToDispatch = false
        for instruction in mainBody {
            switch instruction {
            case .beginFinallyGuard:
                inGuard = true
            case .endFinallyGuard:
                inGuard = false
            case let .call(_, callee, _, _, _, thrownResult, _, _) where inGuard:
                if ctx.interner.resolve(callee) == "get" {
                    accessorThrownResult = thrownResult
                }
            case let .jumpIfNotNull(value, _) where inGuard:
                if value == accessorThrownResult {
                    routedToDispatch = true
                }
            default:
                break
            }
        }
        let slot = try #require(
            accessorThrownResult,
            "expected the synthesized `get` accessor call to carry a thrownResult even without a wired sibling"
        )
        #expect(
            routedToDispatch,
            "the accessor call must be followed by jumpIfNotNull(\(slot)) routing to the catch dispatch"
        )
    }
}
#endif
