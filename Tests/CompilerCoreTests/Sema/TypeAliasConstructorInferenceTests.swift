@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeAliasConstructorInferenceTests {
    private func context(_ source: String, includeStdlib: Bool = false) throws -> CompilationContext {
        let ctx = makeCompilationContext(inputs: ["/typealias-constructor.kt"], includeStdlib: includeStdlib)
        _ = ctx.sourceManager.addFile(path: "/typealias-constructor.kt", contents: Data(source.utf8))
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [
        "ST<String>(\"O\", \"K\")", "ST(\"O\", \"K\")",
        "TextPayload<Int>(\"x\", 1)", "TextPayload(\"x\", 1)", "TextPayload<Long>(\"x\", 1)",
        "Both<String, Int>(\"x\", 1)", "Fixed(\"O\", \"K\")",
        "Pair<String, Int>(\"x\", 1)", "Reversed<Int, String>(\"x\", 1)",
        "Chained<Int>(\"x\", 1)", "Repeated<String>(\"O\", \"K\")",
    ])
    func validCallsPreserveOwnerArguments(call: String) throws {
        let ctx = try context("""
        class Pair<A, B>(val first: A, val second: B)
        typealias ST<T> = Pair<String, T>
        typealias TextPayload<T> = Pair<String, T>
        typealias Both<X, Y> = Pair<X, Y>
        typealias Fixed = Pair<String, String>
        typealias Reversed<X, Y> = Pair<Y, X>
        typealias Chained<T> = ST<T>
        typealias Repeated<T> = Pair<T, T>
        fun make() = \(call)
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let make = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("make")]))
        let result = try #require(sema.symbols.functionSignature(for: make)).returnType
        guard case let .classType(owner) = sema.types.kind(of: result) else {
            Issue.record("Expected Pair result, got \(sema.types.kind(of: result))")
            return
        }
        let second = call.contains("<Long>") ? sema.types.longType
            : call.contains("1)") ? sema.types.intType : sema.types.stringType
        #expect(owner.args == [.invariant(sema.types.stringType), .invariant(second)])
        let binding = try #require(sema.bindings.callBindings.values.first {
            sema.symbols.symbol($0.chosenCallee)?.kind == .constructor
        })
        #expect(binding.substitutedTypeArguments == [sema.types.stringType, second])
    }

    @Test(arguments: [
        "TextPayload(1, \"K\")", "TextPayload<Int>(\"x\", \"bad\")",
        "TextPayload<String, Int>(\"x\", 1)", "Fixed(1, \"K\")",
        "Fixed<Int>(\"O\", \"K\")", "TextPayload(null, 1)",
    ])
    func invalidCallsRemainRejected(call: String) throws {
        let ctx = try context("""
        class Payload<A, B>(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        typealias Fixed = Payload<String, String>
        fun reject() = \(call)
        """)
        #expect(ctx.diagnostics.hasError)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        if call.contains("String, Int>") || call.contains("Fixed<Int>") {
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0062" })
        } else {
            #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0062" })
        }
    }

    @Test func originalGenericTypeAliasConstructor2FixtureIsAccepted() throws {
        let ctx = try context("""
        class Pair<T1, T2>(val x1: T1, val x2: T2)

        typealias ST<T> = Pair<String, T>

        fun box(): String {
            val st = ST<String>("O", "K")
            return st.x1 + st.x2
        }
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func covariantOwnerCannotWidenFixedConstructorSlot() throws {
        let ctx = try context("""
        class Payload<out A, out B>(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        fun reject() = TextPayload(1, "K")
        """)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func explicitAliasTypesContextualizeNestedCallsInOwnerOrder() throws {
        let ctx = try context("""
        class Payload<A, B>(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        typealias Reversed<X, Y> = Payload<Y, X>
        fun text(): String = "x"
        fun number(): Int = 1
        fun make() = TextPayload<Int>(text(), number())
        fun reversed() = Reversed<Int, String>(text(), number())
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func explicitAliasArgumentInsideNestedOwnerSlotIsPreserved() throws {
        let ctx = try context("""
        class Box<T>(val value: T)
        class Payload<A, B>(val first: A, val second: B)
        typealias Nested<T> = Payload<String, Box<T>>
        fun make(): Payload<String, Box<Int>> = Nested<Int>("x", Box(1))
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func inferredNullableAndNestedArgumentsRemainConcrete() throws {
        let ctx = try context("""
        class Box<T>(val value: T)
        class Payload<A, B>(val first: A, val second: B)
        typealias NullablePayload<T> = Payload<String, T?>
        typealias NestedPayload<T> = Payload<String, Box<T>>
        fun nullable() = NullablePayload("x", 1)
        fun nested() = NestedPayload("x", Box(1))
        fun checkNullable(): Payload<String, Int?> = nullable()
        fun checkNested(): Payload<String, Box<Int>> = nested()
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let function = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("nullable")]))
        let result = try #require(sema.symbols.functionSignature(for: function)).returnType
        guard case let .classType(owner) = sema.types.kind(of: result) else {
            Issue.record("Expected Payload result")
            return
        }
        #expect(owner.args == [.invariant(sema.types.stringType), .invariant(sema.types.makeNullable(sema.types.intType))])
    }

    @Test func expectedTypeAndNullableSlotKeepAliasMapping() throws {
        let ctx = try context("""
        class Payload<A, B>(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        typealias NullableText<T> = Payload<String?, T>
        fun expected(): Payload<String, Int> = TextPayload("x", 1)
        fun nullable(): Payload<String?, Int> = NullableText(null, 1)
        fun <T> generic(value: T): Payload<String, T> = TextPayload("x", value)
        fun direct(): Payload<String, String> = Payload<String, String>("O", "K")
        fun directWide(): Payload<Any, String> = Payload("O", "K")
        fun full(): Payload<String, String> = Both<String, String>("O", "K")
        fun fixed(): Payload<String, String> = Fixed("O", "K")
        typealias Both<X, Y> = Payload<X, Y>
        typealias Fixed = Payload<String, String>
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["Bounded<Int>(\"x\", 1)", "Bounded(\"x\", 1)"])
    func underlyingUpperBoundRemainsEnforced(call: String) throws {
        let ctx = try context("""
        class Payload<A, B : String>(val first: A, val second: B)
        typealias Bounded<T> = Payload<String, T>
        fun reject() = \(call)
        """)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-BOUND" })
    }

    @Test(arguments: ["Int", "Any"])
    func expectedTypeCannotReplaceFixedSlot(expectedFirst: String) throws {
        let ctx = try context("""
        class Payload<A, B>(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        fun reject(): Payload<\(expectedFirst), String> = TextPayload("x", "K")
        """)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func validUnderlyingUpperBoundIsAccepted() throws {
        let ctx = try context("""
        class Payload<A, B : String>(val first: A, val second: B)
        typealias Bounded<T> = Payload<String, T>
        fun make() = Bounded<String>("O", "K")
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func privateUnderlyingConstructorRemainsInvisible() throws {
        let ctx = try context("""
        class Payload<A, B> private constructor(val first: A, val second: B)
        typealias TextPayload<T> = Payload<String, T>
        fun reject() = TextPayload<Int>("x", 1)
        """)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func arrayTypeAliasConstructorsResolveWithoutPrivateAccessError() throws {
        let ctx = try context("""
        typealias BoolArray = Array<Boolean>
        typealias IArray = IntArray
        typealias MyArray<T> = Array<T>

        fun box(): String {
            val ba = BoolArray(1) { true }
            if (!ba[0]) return "Fail #1"

            val ia = IArray(1) { 42 }
            if (ia[0] != 42) return "Fail #2"

            val ma = MyArray<Int>(1) { 42 }
            if (ma[0] != 42) return "Fail #2"

            return "OK"
        }
        """, includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func privateArrayTypeAliasConstructorRejectsCrossFileAccess() throws {
        let ctx = makeCompilationContext(
            inputs: ["/file1.kt", "/file2.kt"],
            includeStdlib: true
        )
        _ = ctx.sourceManager.addFile(
            path: "/file1.kt",
            contents: Data("package test\nprivate typealias PrivateArray<T> = Array<T>\n".utf8)
        )
        _ = ctx.sourceManager.addFile(
            path: "/file2.kt",
            contents: Data("package test\nfun test() { val a = PrivateArray<Int>(1) { 42 } }\n".utf8)
        )
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0040" })
    }

    @Test func inferredGenericArrayTypeAliasConstructorResolves() throws {
        let ctx = try context("""
        typealias MyArray<T> = Array<T>
        fun test() {
            val ma = MyArray(1) { 42 }
            val str = MyArray(1) { "hello" }
        }
        """, includeStdlib: true)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
