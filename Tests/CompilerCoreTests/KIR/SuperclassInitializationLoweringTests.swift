#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for BUG-155: a subclass instance kept the default
/// (zeroed) values of its inherited fields because the subclass constructor
/// never ran the superclass constructor, and a base-class method calling an
/// overridable member through the implicit receiver dispatched statically to
/// the base implementation.
@Suite
struct SuperclassInitializationLoweringTests {
    private static let source = """
    abstract class Base {
        var flag: Int = 7
        fun run(): Unit = compute()
        protected abstract fun compute(): Unit
    }
    class Impl : Base() {
        override fun compute() {
            flag = 1
        }
    }
    open class BaseWithArguments(val value: Int, val offset: Int) {
        val adjusted: Int = value * 2 + offset
    }
    class DerivedWithArguments(
        val source: Int,
        val delta: Int
    ) : BaseWithArguments(source, delta)
    fun main() {
        val impl = Impl()
        println(impl.flag)
        impl.run()
        println(impl.flag)
        println(DerivedWithArguments(3, 1).adjusted)
    }
    """

    @Test func testSubclassConstructorRunsSuperclassConstructor() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "Impl", in: module, interner: ctx.interner)
            #expect(extractCallees(from: body, interner: ctx.interner).contains("<init>"))
        }
    }

    @Test func testImplicitReceiverCallToOverridableMemberUsesVirtualDispatch() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "run", in: module, interner: ctx.interner)
            #expect(body.contains { instruction in
                guard case .virtualCall = instruction else { return false }
                return true
            })
        }
    }

    @Test func testPrimarySuperclassConstructorForwardsArguments() throws {
        try withTemporaryFile(contents: Self.source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let body = try findKIRFunctionBody(
                named: "DerivedWithArguments",
                in: module,
                interner: ctx.interner
            )
            let call = try #require(body.first { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "<init>"
            })
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = call else {
                Issue.record("Expected superclass constructor call")
                return
            }

            let target = try #require(symbol)
            #expect(sema.symbols.functionSignature(for: target)?.parameterTypes.count == 2)
            #expect(arguments.count == 3)
            let forwardedArguments = arguments.dropFirst().compactMap { argument -> SymbolID? in
                guard case let .symbolRef(parameterSymbol)? = module.arena.expr(argument) else {
                    return nil
                }
                return parameterSymbol
            }
            let parameterNames = forwardedArguments.compactMap {
                sema.symbols.symbol($0).map { ctx.interner.resolve($0.name) }
            }
            guard parameterNames.count == 2 else {
                Issue.record("Expected both superclass arguments to reference derived constructor parameters")
                return
            }
            #expect(parameterNames == ["source", "delta"])
        }
    }
}
#endif
