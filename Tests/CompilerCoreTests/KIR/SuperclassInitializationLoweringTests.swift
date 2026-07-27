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
    fun main() {
        val impl = Impl()
        println(impl.flag)
        impl.run()
        println(impl.flag)
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
}
#endif
