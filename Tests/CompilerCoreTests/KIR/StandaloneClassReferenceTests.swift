#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Tests for REFL-002: standalone `T::class` references produce proper KClass
/// metadata via `__kk_kclass_create` instead of falling back to Unit.
@Suite
struct StandaloneClassReferenceTests {

    /// Standalone `T::class` inside a reified inline function should emit
    /// `__kk_kclass_create` in the lowered KIR output after inline expansion.
    @Test func testStandaloneReifiedClassRefEmitsKClassCreate() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun main() {
            val kc = classOf<Int>()
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            // Run through lowering so inline expansion processes T::class.
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone T::class after inline expansion, got: \(callees)"
            )
        }
    }

    /// Standalone `String::class` (concrete/builtin type) should emit
    /// `__kk_kclass_create` in the KIR output.
    @Test func testStandaloneConcreteClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = String::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone String::class, got: \(callees)"
            )
        }
    }

    /// Standalone `Int::class` (primitive builtin type) should emit
    /// `__kk_kclass_create` in the KIR output.
    @Test func testStandalonePrimitiveClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone Int::class, got: \(callees)"
            )
        }
    }

    /// `T::class.simpleName` (chained) after inline expansion.
    ///
    /// KSP-496 moved `simpleName` to an ordinary Kotlin extension property
    /// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt), so
    /// `T::class` now always creates the KClass box (`__kk_kclass_create`)
    /// before dispatching to the `simpleName` getter — there is no longer a
    /// "direct path" that skips box creation for this member.
    @Test func testChainedClassRefSimpleNameUsesDirectPath() throws {
        let source = """
        inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"
        fun main() = println(typeNameOf<Int>())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("simpleName"),
                "Chained T::class.simpleName should resolve to the Kotlin simpleName getter, got: \(callees)"
            )
            #expect(
                callees.contains("__kk_kclass_create"),
                "Chained T::class.simpleName should emit __kk_kclass_create (box creation, then dispatch to the simpleName getter), got: \(callees)"
            )
        }
    }

    /// User-defined class `MyClass::class` should emit `__kk_kclass_create`.
    @Test func testStandaloneUserClassRefEmitsKClassCreate() throws {
        let source = """
        class MyClass
        fun main() {
            val kc = MyClass::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone MyClass::class, got: \(callees)"
            )
        }
    }

    @Test func testFindAssociatedObjectLowersToRuntimeCall() throws {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects
        import kotlin.reflect.findAssociatedObject

        annotation class Binding
        class Host

        @OptIn(ExperimentalAssociatedObjects::class)
        fun main() {
            val associated = Host::class.findAssociatedObject<Binding>()
            println(associated)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_find_associated_object"),
                "Expected findAssociatedObject to lower to __kk_kclass_find_associated_object, got: \(callees)"
            )
        }
    }

    // MARK: - REFL-002 Additional tests

    /// `this::class` inside a class method should emit `__kk_kclass_create`.
    @Test func testThisClassRefEmitsKClassCreate() throws {
        let source = """
        class Foo {
            fun getKClass(): Any = this::class
        }
        fun main() {
            val f = Foo()
            println(f.getKClass())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            // Check that classRefTargetType was bound for the this::class expr
            // by looking for __kk_kclass_create in the Foo.getKClass body.
            let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for this::class, got: \(callees)"
            )
        }
    }

    /// `Long::class` should emit `__kk_kclass_create` with a non-zero type token.
    @Test func testStandaloneLongClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Long::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone Long::class, got: \(callees)"
            )
        }
    }

    /// `Double::class` should emit `__kk_kclass_create`.
    @Test func testStandaloneDoubleClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Double::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone Double::class, got: \(callees)"
            )
        }
    }

    /// `Boolean::class` should emit `__kk_kclass_create`.
    @Test func testStandaloneBooleanClassRefEmitsKClassCreate() throws {
        let source = """
        fun main() {
            val kc = Boolean::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                "Expected __kk_kclass_create for standalone Boolean::class, got: \(callees)"
            )
        }
    }

    /// RuntimeTypeCheckToken should encode Long as a distinct (non-zero) base.
    @Test func testRuntimeTypeCheckTokenEncodesLong() {
        let (sema, _, types, interner) = makeSemaModule()
        let longType = types.make(.primitive(.long, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: longType, sema: sema, interner: interner)
        // longBase = 11
        #expect(encoded & 0xFF == 11, "Long should encode with base 11, got \(encoded & 0xFF)")
        #expect(encoded != 0, "Long token must not be unknownBase (0)")
    }

    /// RuntimeTypeCheckToken should encode Double as a distinct base.
    @Test func testRuntimeTypeCheckTokenEncodesDouble() {
        let (sema, _, types, interner) = makeSemaModule()
        let doubleType = types.make(.primitive(.double, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: doubleType, sema: sema, interner: interner)
        // doubleBase = 12
        #expect(encoded & 0xFF == 12, "Double should encode with base 12, got \(encoded & 0xFF)")
    }

    /// RuntimeTypeCheckToken should encode Float as a distinct base.
    @Test func testRuntimeTypeCheckTokenEncodesFloat() {
        let (sema, _, types, interner) = makeSemaModule()
        let floatType = types.make(.primitive(.float, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: floatType, sema: sema, interner: interner)
        // floatBase = 13
        #expect(encoded & 0xFF == 13, "Float should encode with base 13, got \(encoded & 0xFF)")
    }

    /// RuntimeTypeCheckToken should encode Char as a distinct base.
    @Test func testRuntimeTypeCheckTokenEncodesChar() {
        let (sema, _, types, interner) = makeSemaModule()
        let charType = types.make(.primitive(.char, .nonNull))
        let encoded = RuntimeTypeCheckToken.encode(type: charType, sema: sema, interner: interner)
        // charBase = 14
        #expect(encoded & 0xFF == 14, "Char should encode with base 14, got \(encoded & 0xFF)")
    }

    /// KIR result type for a standalone `Int::class` should carry a KClass type
    /// rather than falling back to Any.
    @Test func testKIRResultTypeIsKClassNotAny() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            // Find the __kk_kclass_create call and check its result type.
            for instruction in body {
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "__kk_kclass_create" {
                    guard let resultID = result,
                          let resultType = module.arena.exprType(resultID) else {
                        Issue.record("__kk_kclass_create result has no stored type")
                        return
                    }
                    // The result type should be KClass<Int>, not Any.
                    if case .kClassType = ctx.sema!.types.kind(of: resultType) {
                        // Success — type is KClass<T>.
                        return
                    }
                    Issue.record("Expected KClass type for __kk_kclass_create result, got type kind: \(ctx.sema!.types.kind(of: resultType))")
                    return
                }
            }
            Issue.record("__kk_kclass_create call not found in main body")
        }
    }

    /// KSP-496: `cast`/`safeCast` are bundled Kotlin extensions
    /// (Stdlib/kotlin/reflect/KClassBasicAPI.kt), so call sites must delegate to
    /// them instead of being special-cased into a direct runtime call.
    private func expectBundledReflectDelegation(
        source: String,
        functions: [String],
        extensionName: String,
        runtimeCallee: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            for functionName in functions {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains(extensionName),
                    "Expected \(functionName) to call the bundled Kotlin \(extensionName) extension"
                )
                #expect(
                    !callees.contains(runtimeCallee),
                    "Expected \(functionName) not to emit \(runtimeCallee) directly"
                )
            }
        }
    }

    @Test func testDirectKClassCastDelegatesToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            fun castString(value: Any?): String = String::class.cast(value)
            """,
            functions: ["castString"],
            extensionName: "cast",
            runtimeCallee: "__kk_kclass_cast"
        )
    }

    @Test func testKClassCastViaLocalAndParameterDelegateToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            import kotlin.reflect.KClass

            fun castViaLocal(value: Any?): String {
                val klass = String::class
                return klass.cast(value)
            }

            fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
            """,
            functions: ["castViaLocal", "castWithClass"],
            extensionName: "cast",
            runtimeCallee: "__kk_kclass_cast"
        )
    }

    @Test func testDirectKClassSafeCastDelegatesToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            fun safeCastString(value: Any?): String? = String::class.safeCast(value)
            """,
            functions: ["safeCastString"],
            extensionName: "safeCast",
            runtimeCallee: "__kk_kclass_safeCast"
        )
    }

    @Test func testKClassSafeCastViaLocalAndParameterDelegateToBundledExtension() throws {
        try expectBundledReflectDelegation(
            source: """
            import kotlin.reflect.KClass

            fun safeCastViaLocal(value: Any?): String? {
                val klass = String::class
                return klass.safeCast(value)
            }

            fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
            """,
            functions: ["safeCastViaLocal", "safeCastWithClass"],
            extensionName: "safeCast",
            runtimeCallee: "__kk_kclass_safeCast"
        )
    }
}
#endif
