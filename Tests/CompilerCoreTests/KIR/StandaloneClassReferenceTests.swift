@testable import CompilerCore
import Foundation
import XCTest

final class StandaloneClassReferenceTests: XCTestCase {

    func testStandaloneReifiedClassRefEmitsKClassCreate() throws {
        let source = """
        inline fun <reified T> classOf(): Any = T::class
        fun main() {
            val kc = classOf<Int>()
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone T::class after inline expansion, got: \(callees)"
            )
        }
    }

    func testStandaloneConcreteAndPrimitiveClassRefsEmitKClassCreate() throws {
        let types = ["String", "Int", "Long", "Double", "Boolean"]
        for typeName in types {
            let source = """
            fun main() {
                val kc = \(typeName)::class
                println(kc)
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
                try runToKIR(ctx)

                let module = try XCTUnwrap(ctx.kir)
                let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
                let callees = extractCallees(from: body, interner: ctx.interner)
                XCTAssertTrue(
                    callees.contains("kk_kclass_create"),
                    "Expected kk_kclass_create for standalone \(typeName)::class, got: \(callees)"
                )
            }
        }
    }

    func testChainedClassRefSimpleNameUsesDirectPath() throws {
        let source = """
        inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"
        fun main() = println(typeNameOf<Int>())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_type_token_simple_name"),
                "Chained T::class.simpleName should use kk_type_token_simple_name, got: \(callees)"
            )
            XCTAssertFalse(
                callees.contains("kk_kclass_create"),
                "Chained T::class.simpleName should NOT emit kk_kclass_create, got: \(callees)"
            )
        }
    }

    func testStandaloneUserClassRefEmitsKClassCreate() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for standalone MyClass::class, got: \(callees)"
            )
        }
    }

    func testFindAssociatedObjectLowersToRuntimeCall() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_find_associated_object"),
                "Expected findAssociatedObject to lower to kk_kclass_find_associated_object, got: \(callees)"
            )
        }
    }

    func testThisClassRefEmitsKClassCreate() throws {
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

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "getKClass", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_kclass_create"),
                "Expected kk_kclass_create for this::class, got: \(callees)"
            )
        }
    }

    func testRuntimeTypeCheckTokenEncodesAdditionalPrimitives() {
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
            XCTAssertEqual(encoded & 0xFF, expectedBase, "\(label) should encode with base \(expectedBase)")
            XCTAssertNotEqual(encoded, 0, "\(label) token must not be unknownBase (0)")
        }
    }

    func testKIRResultTypeIsKClassNotAny() throws {
        let source = """
        fun main() {
            val kc = Int::class
            println(kc)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            for instruction in body {
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction else { continue }
                if ctx.interner.resolve(callee) == "kk_kclass_create" {
                    guard let resultID = result,
                          let resultType = module.arena.exprType(resultID) else {
                        XCTFail("kk_kclass_create result has no stored type")
                        return
                    }
                    if case .kClassType = ctx.sema!.types.kind(of: resultType) {
                        return
                    }
                    XCTFail("Expected KClass type for kk_kclass_create result, got type kind: \(ctx.sema!.types.kind(of: resultType))")
                    return
                }
            }
            XCTFail("kk_kclass_create call not found in main body")
        }
    }

    func testDirectKClassCastEmitsThrowingRuntimeCall() throws {
        let source = """
        fun castString(value: Any?): String = String::class.cast(value)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "castString", in: module, interner: ctx.interner)
            XCTAssertTrue(
                body.contains { instruction in
                    guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_kclass_cast" && canThrow
                },
                "Expected String::class.cast to lower to throwing kk_kclass_cast"
            )
        }
    }

    func testKClassCastViaLocalAndParameterEmitRuntimeCall() throws {
        let source = """
        import kotlin.reflect.KClass

        fun castViaLocal(value: Any?): String {
            val klass = String::class
            return klass.cast(value)
        }

        fun <T : Any> castWithClass(klass: KClass<T>, value: Any?): T = klass.cast(value)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            for functionName in ["castViaLocal", "castWithClass"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                XCTAssertTrue(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "kk_kclass_cast" && canThrow
                    },
                    "Expected \(functionName) to lower to throwing kk_kclass_cast"
                )
            }
        }
    }

    func testDirectKClassSafeCastEmitsNonThrowingRuntimeCall() throws {
        let source = """
        fun safeCastString(value: Any?): String? = String::class.safeCast(value)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "safeCastString", in: module, interner: ctx.interner)
            XCTAssertTrue(
                body.contains { instruction in
                    guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                    return ctx.interner.resolve(callee) == "kk_kclass_safeCast" && !canThrow
                },
                "Expected String::class.safeCast to lower to non-throwing kk_kclass_safeCast"
            )
        }
    }

    func testKClassSafeCastViaLocalAndParameterEmitRuntimeCall() throws {
        let source = """
        import kotlin.reflect.KClass

        fun safeCastViaLocal(value: Any?): String? {
            val klass = String::class
            return klass.safeCast(value)
        }

        fun <T : Any> safeCastWithClass(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            for functionName in ["safeCastViaLocal", "safeCastWithClass"] {
                let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
                XCTAssertTrue(
                    body.contains { instruction in
                        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return false }
                        return ctx.interner.resolve(callee) == "kk_kclass_safeCast" && !canThrow
                    },
                    "Expected \(functionName) to lower to non-throwing kk_kclass_safeCast"
                )
            }
        }
    }
}
