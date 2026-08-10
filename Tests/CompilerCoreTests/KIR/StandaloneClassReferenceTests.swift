#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Tests for REFL-002: standalone `T::class` references produce proper KClass
/// metadata via `__kk_kclass_create` instead of falling back to Unit.
@Suite
struct StandaloneClassReferenceTests {

    // MARK: - Class reference KIR lowering (requires inline expansion)

    @Test func testLoweringClassRefEmissions() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun mainReified() {
            val kc = classOf<Int>()
            println(kc)
        }

        inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"
        fun mainChained() = println(typeNameOf<Int>())
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)

            do {
                let body = try findKIRFunctionBody(named: "mainReified", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for standalone T::class after inline expansion, got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "mainChained", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("simpleName"),
                    "Chained T::class.simpleName should resolve to the Kotlin simpleName getter, got: \(callees)"
                )
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Chained T::class.simpleName should emit __kk_kclass_create, got: \(callees)"
                )
            }
        }
    }

    // MARK: - Class reference KIR emissions

    @Test func testKIRClassRefAndCastEmissions() throws {
        let sources: [String] = [
            """
            fun mainConcrete() {
                val kc = String::class
                println(kc)
            }
            """,
            """
            fun mainPrimitive() {
                val kc = Int::class
                println(kc)
            }
            """,
            """
            class MyClass
            fun mainUser() {
                val kc = MyClass::class
                println(kc)
            }
            """,
            """
            import kotlin.reflect.ExperimentalAssociatedObjects
            import kotlin.reflect.findAssociatedObject

            annotation class Binding
            class Host

            @OptIn(ExperimentalAssociatedObjects::class)
            fun mainAssociated() {
                val associated = Host::class.findAssociatedObject<Binding>()
                println(associated)
            }
            """,
            """
            class Foo {
                fun getKClass(): Any = this::class
            }
            fun mainThis() {
                val f = Foo()
                println(f.getKClass())
            }
            """,
            """
            fun mainLong() {
                val kc = Long::class
                println(kc)
            }
            """,
            """
            fun mainDouble() {
                val kc = Double::class
                println(kc)
            }
            """,
            """
            fun mainBoolean() {
                val kc = Boolean::class
                println(kc)
            }
            """,
            """
            fun castString(value: Any?): String = String::class.cast(value)
            """,
            """
            import kotlin.reflect.KClass

            fun castViaLocal(value: Any?): String {
                val klass = String::class
                return klass.cast(value)
            }

            fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
            """,
            """
            fun safeCastString(value: Any?): String? = String::class.safeCast(value)
            """,
            """
            import kotlin.reflect.KClass

            fun safeCastViaLocal(value: Any?): String? {
                val klass = String::class
                return klass.safeCast(value)
            }

            fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            do {
                let body = try findKIRFunctionBody(named: "mainConcrete", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for standalone String::class, got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "mainPrimitive", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for standalone Int::class, got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "mainPrimitive", in: module, interner: ctx.interner)
                // Find the __kk_kclass_create call and check its result type.
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
                Issue.record("__kk_kclass_create call not found in mainPrimitive body")
            }

            do {
                let body = try findKIRFunctionBody(named: "mainUser", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for standalone MyClass::class, got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "mainAssociated", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_find_associated_object"),
                    "Expected findAssociatedObject to lower to __kk_kclass_find_associated_object, got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for this::class, got: \(callees)"
                )
            }

            for name in ["mainLong", "mainDouble", "mainBoolean"] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                #expect(
                    callees.contains("__kk_kclass_create"),
                    "Expected __kk_kclass_create for standalone primitive class ref in \(name), got: \(callees)"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "castString", in: module, interner: ctx.interner)
                #expect(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "__kk_kclass_cast" && canThrow
                    },
                    "Expected String::class.cast to lower to throwing __kk_kclass_cast"
                )
            }

            for functionName in ["castViaLocal", "castWithClass"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                #expect(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "__kk_kclass_cast" && canThrow
                    },
                    "Expected \(functionName) to lower to throwing __kk_kclass_cast"
                )
            }

            do {
                let body = try findKIRFunctionBody(named: "safeCastString", in: module, interner: ctx.interner)
                #expect(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "__kk_kclass_safeCast" && !canThrow
                    },
                    "Expected String::class.safeCast to lower to non-throwing __kk_kclass_safeCast"
                )
            }

            for functionName in ["safeCastViaLocal", "safeCastWithClass"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                #expect(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "__kk_kclass_safeCast" && !canThrow
                    },
                    "Expected \(functionName) to lower to non-throwing __kk_kclass_safeCast"
                )
            }
        }
    }

    // MARK: - RuntimeTypeCheckToken encoding

    @Test func testRuntimeTypeCheckTokenEncodings() {
        let (sema, _, types, interner) = makeSemaModule()

        let longType = types.make(.primitive(.long, .nonNull))
        let longEncoded = RuntimeTypeCheckToken.encode(type: longType, sema: sema, interner: interner)
        #expect(longEncoded & 0xFF == 11, "Long should encode with base 11, got \(longEncoded & 0xFF)")
        #expect(longEncoded != 0, "Long token must not be unknownBase (0)")

        let doubleType = types.make(.primitive(.double, .nonNull))
        let doubleEncoded = RuntimeTypeCheckToken.encode(type: doubleType, sema: sema, interner: interner)
        #expect(doubleEncoded & 0xFF == 12, "Double should encode with base 12, got \(doubleEncoded & 0xFF)")

        let floatType = types.make(.primitive(.float, .nonNull))
        let floatEncoded = RuntimeTypeCheckToken.encode(type: floatType, sema: sema, interner: interner)
        #expect(floatEncoded & 0xFF == 13, "Float should encode with base 13, got \(floatEncoded & 0xFF)")

        let charType = types.make(.primitive(.char, .nonNull))
        let charEncoded = RuntimeTypeCheckToken.encode(type: charType, sema: sema, interner: interner)
        #expect(charEncoded & 0xFF == 14, "Char should encode with base 14, got \(charEncoded & 0xFF)")
    }
}
#endif
