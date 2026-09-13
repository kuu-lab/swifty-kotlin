#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct StandaloneClassReferenceTests {

    @Test func testStandaloneReifiedClassRefEmitsKClassCreate() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun main() {
            val kc = classOf<Int>()
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("__kk_kclass_create"),
            "Expected __kk_kclass_create for standalone T::class after inline expansion, got: \(callees)"
        )
    }

    @Test func testStandaloneConcreteAndPrimitiveClassRefsEmitKClassCreate() throws {
        for typeName in ["String", "Int", "Long", "Double", "Boolean"] {
            let source = """
            fun main() {
                val kc = \(typeName)::class
                println(kc)
            }
            """
            let ctx = makeContextFromSource(source)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                callees.contains("__kk_kclass_create"),
                Comment(rawValue: "Expected __kk_kclass_create for standalone \(typeName)::class, got: \(callees)")
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
        let ctx = makeContextFromSource(source)
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

    @Test func testStandaloneUserClassRefEmitsKClassCreate() throws {
        let source = """
        class MyClass
        fun main() {
            val kc = MyClass::class
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("__kk_kclass_create"),
            "Expected __kk_kclass_create for standalone MyClass::class, got: \(callees)"
        )
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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("__kk_kclass_find_associated_object"),
            "Expected findAssociatedObject to lower to __kk_kclass_find_associated_object, got: \(callees)"
        )
    }

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
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(
            callees.contains("__kk_kclass_create"),
            "Expected __kk_kclass_create for this::class, got: \(callees)"
        )
    }

    @Test func testRuntimeTypeCheckTokenEncodesAdditionalPrimitives() {
        let cases: [(PrimitiveType, Int64, String)] = [
            (.long, 11, "Long"),
            (.double, 12, "Double"),
            (.float, 13, "Float"),
            (.char, 14, "Char"),
        ]
        let (sema, _, types, interner) = makeSemaModule()
        for (kind, expectedBase, label) in cases {
            let type = types.make(.primitive(kind, .nonNull))
            let encoded = RuntimeTypeCheckToken.encode(type: type, sema: sema, interner: interner)
            #expect(encoded & 0xFF == expectedBase, Comment(rawValue: "\(label) should encode with base \(expectedBase)"))
            #expect(encoded != 0, Comment(rawValue: "\(label) token must not be unknownBase (0)"))
        }
    }

    @Test func testKIRResultTypeIsKClassNotAny() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        for instruction in body {
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction else { continue }
            if ctx.interner.resolve(callee) == "__kk_kclass_create" {
                guard let resultID = result,
                      let resultType = module.arena.exprType(resultID) else {
                    Issue.record("__kk_kclass_create result has no stored type")
                    return
                }
                if case .kClassType = ctx.sema!.types.kind(of: resultType) {
                    return
                }
                Issue.record("Expected KClass type for __kk_kclass_create result, got type kind: \(ctx.sema!.types.kind(of: resultType))")
                return
            }
        }
        Issue.record("__kk_kclass_create call not found in main body")
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
        let ctx = makeContextFromSource(source)
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
