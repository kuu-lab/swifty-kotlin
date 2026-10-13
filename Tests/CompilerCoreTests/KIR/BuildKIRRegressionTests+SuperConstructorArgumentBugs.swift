#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for superclass constructor calls that dropped named
/// arguments / defaults or the state handed to a runtime-backed Exception
/// constructor. The executable counterpart is
/// `Scripts/diff_cases/super_ctor_named_defaults_and_throwable_factories.kt`.
extension BuildKIRRegressionTests {
    @Test(arguments: [
        "object Derived : Base(transform = { it + \"!\" })",
        "class Derived : Base(transform = { it + \"!\" })",
        "class Derived : Base { constructor() : super(transform = { it + \"!\" }) }",
        "fun make() = object : Base(transform = { it + \"!\" }) {}",
    ])
    func constructorDelegationMaterializesLambdaFunctionValues(declaration: String) throws {
        let source = """
        open class Base(val label: String = "base", val transform: (String) -> String)
        \(declaration)
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let delegatesWithFunctionValue = findAllKIRFunctions(in: module).contains { function in
            let callees = extractCallees(from: function.body, interner: ctx.interner)
            return callees.contains(runtimeCallee(.functionCreate1)) && callees.contains("Base$default")
        }
        #expect(delegatesWithFunctionValue)
    }

    @Test(arguments: [
        "object Cast : Holder({ value -> value as? String })",
        "class Cast : Holder(f = { value -> value as? String })",
        "class Cast : Holder { constructor() : super({ value -> value as? String }) }",
        "class Cast(f: (Any) -> String?) : Holder(f) { constructor() : this({ value -> value as? String }) }",
        "object Cast : Holder(f = { value -> value as? String }, marker = 9)",
        "object Cast : Holder(f = { value -> value as? String })",
    ])
    func constructorDelegationMaterializesLambdaArguments(declaration: String) throws {
        let source = """
        open class Holder(val marker: Int = 7, val f: (Any) -> String?) {
            constructor(f: (Any) -> String?) : this(7, f)
        }
        \(declaration)
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let delegatesWithFunctionValue = findAllKIRFunctions(in: module).contains { function in
            for (index, instruction) in function.body.enumerated() {
                guard case let .call(_, callee, _, materialized?, _, _, _, _) = instruction,
                      callee == ctx.interner.intern(runtimeCallee(.functionCreate1))
                else { continue }
                if function.body.dropFirst(index + 1).contains(where: { instruction in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else { return false }
                    return ["<init>", "Holder$default"].contains(ctx.interner.resolve(callee))
                        && arguments.contains(materialized)
                }) {
                    return true
                }
            }
            return false
        }
        #expect(delegatesWithFunctionValue)
    }

    /// `object O : Base()` used to call `Base.<init>` with no arguments,
    /// reading garbage for both defaulted parameters.
    @Test
    func namedObjectSuperCallWithOmittedDefaultsRoutesThroughDefaultStub() throws {
        let source = """
        open class Base(val x: Int = 7, val y: Int = 8)
        object O : Base()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let delegatesThroughStub = findAllKIRFunctions(in: module).contains { function in
            extractCallees(from: function.body, interner: ctx.interner).contains("Base$default")
        }
        #expect(delegatesThroughStub, "Expected O's super call to use Base$default")
    }

    /// `constructor(msg: String) : super(msg)` on an Exception subclass used to
    /// call the runtime factory and drop the box it returned, so `message`
    /// stayed null.
    @Test
    func secondaryConstructorSuperCallToExceptionFactoryCopiesMessage() throws {
        let source = """
        class MyEx : Exception {
            constructor(msg: String) : super(msg)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let ctorCallees = findAllKIRFunctions(in: module)
            .filter { $0.name == ctx.interner.intern("MyEx") }
            .flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
        #expect(ctorCallees.contains(runtimeCallee(.exceptionNewMessage)), "Got: \(ctorCallees)")
        #expect(ctorCallees.contains(runtimeCallee(.throwableSetMessage)), "Got: \(ctorCallees)")
        #expect(!ctorCallees.contains("<init>"), "Got: \(ctorCallees)")
    }

    /// A cause-only `Exception(c)` header fell through every positional
    /// special case (which required a `String?` first parameter), losing the
    /// cause.
    @Test
    func causeOnlyExceptionSuperCallCopiesCause() throws {
        let source = """
        class E(c: Throwable) : Exception(c)
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)

        let ctorCallees = findAllKIRFunctions(in: module)
            .filter { $0.name == ctx.interner.intern("E") }
            .flatMap { extractCallees(from: $0.body, interner: ctx.interner) }
        #expect(ctorCallees.contains(runtimeCallee(.exceptionNewCause)), "Got: \(ctorCallees)")
        #expect(ctorCallees.contains(runtimeCallee(.throwableSetCause)), "Got: \(ctorCallees)")
        #expect(ctorCallees.contains(runtimeCallee(.throwableSetMessage)), "Got: \(ctorCallees)")
    }
}
#endif
