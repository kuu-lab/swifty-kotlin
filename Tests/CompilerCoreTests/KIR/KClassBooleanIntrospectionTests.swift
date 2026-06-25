@testable import CompilerCore
import Foundation
import XCTest

final class KClassBooleanIntrospectionTests: XCTestCase {

    private func calleesForMain(_ source: String) throws -> Set<String> {
        var result: Set<String>?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            result = Set(extractCallees(from: body, interner: ctx.interner))
        }
        return try XCTUnwrap(result)
    }

    func testClassLiteralIsDataEmitsRuntimeCallAndMetadata() throws {
        let callees = try calleesForMain("""
        data class Point(val x: Int)
        fun main() {
            println(Point::class.isData)
        }
        """)
        XCTAssertTrue(
            callees.contains("kk_kclass_is_data"),
            "Point::class.isData should lower to kk_kclass_is_data, got: \(callees)"
        )
        // The flag bits are read from the metadata registry, so the literal-class
        // query must also register the metadata (keyed by the same type token).
        XCTAssertTrue(
            callees.contains("kk_kclass_register_metadata"),
            "Point::class.isData should register metadata so the flag resolves, got: \(callees)"
        )
    }

    func testClassLiteralIsSealedEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        sealed class Shape
        fun main() {
            println(Shape::class.isSealed)
        }
        """)
        XCTAssertTrue(
            callees.contains("kk_kclass_is_sealed"),
            "Shape::class.isSealed should lower to kk_kclass_is_sealed, got: \(callees)"
        )
    }

    func testClassLiteralIsValueEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        @JvmInline
        value class Wrapped(val v: Int)
        fun main() {
            println(Wrapped::class.isValue)
        }
        """)
        XCTAssertTrue(
            callees.contains("kk_kclass_is_value"),
            "Wrapped::class.isValue should lower to kk_kclass_is_value, got: \(callees)"
        )
    }

    func testClassLiteralTypeKindMembersEmitRuntimeCalls() throws {
        let cases: [(decl: String, ref: String, member: String, callee: String)] = [
            ("enum class Color { RED }", "Color", "isEnum", "kk_kclass_is_enum"),
            ("interface Iface", "Iface", "isInterface", "kk_kclass_is_interface"),
            ("object Singleton", "Singleton", "isObject", "kk_kclass_is_object"),
            ("fun interface F { fun run() }", "F", "isFun", "kk_kclass_is_fun"),
        ]
        for testCase in cases {
            let callees = try calleesForMain("""
            \(testCase.decl)
            fun main() {
                println(\(testCase.ref)::class.\(testCase.member))
            }
            """)
            XCTAssertTrue(
                callees.contains(testCase.callee),
                "\(testCase.ref)::class.\(testCase.member) should lower to \(testCase.callee), got: \(callees)"
            )
        }
    }

    func testVariableReceiverIsDataEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun main() {
            val k: KClass<Point> = Point::class
            println(k.isData)
        }
        """)
        XCTAssertTrue(
            callees.contains("kk_kclass_is_data"),
            "k.isData on a KClass<Point> variable should lower to kk_kclass_is_data "
                + "(not fall through to an undefined _isData symbol), got: \(callees)"
        )
    }

    func testVariableReceiverStandaloneClassRefRegistersMetadata() throws {
        // A standalone `T::class` stored in a variable must register metadata so a
        // later `k.isData` resolves the flag even when the class is never built.
        let callees = try calleesForMain("""
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun main() {
            val k: KClass<Point> = Point::class
            println(k.isData)
        }
        """)
        XCTAssertTrue(
            callees.contains("kk_kclass_register_metadata"),
            "Standalone Point::class should register metadata, got: \(callees)"
        )
    }
}
