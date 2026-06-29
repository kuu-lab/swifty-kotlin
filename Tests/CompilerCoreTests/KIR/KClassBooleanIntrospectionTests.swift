#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-REFLECT-067: KClass kind/modifier boolean introspection
/// (`isData` / `isSealed` / `isValue`) lowering.
///
/// These members are end-to-end wired (Sema inference → KIR lowering → runtime),
/// so the tests assert that the expected runtime callee is emitted for both
/// receiver forms:
/// - a compile-time class literal (`Foo::class.isData`), and
/// - a stored `KClass<T>` variable (`val k: KClass<Foo> = Foo::class; k.isData`),
///   which exercises the `.classType`-wrapping-KClass receiver representation.
@Suite @MainActor
struct KClassBooleanIntrospectionTests {

    private func calleesForMain(_ source: String) throws -> Set<String> {
        var result: Set<String>?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            result = Set(extractCallees(from: body, interner: ctx.interner))
        }
        return try #require(result)
    }

    // MARK: - Class-literal receiver

    @Test func testClassLiteralIsDataEmitsRuntimeCallAndMetadata() throws {
        let callees = try calleesForMain("""
        data class Point(val x: Int)
        fun main() {
            println(Point::class.isData)
        }
        """)
        #expect(
            callees.contains("kk_kclass_is_data"),
            "Point::class.isData should lower to kk_kclass_is_data, got: \(callees)"
        )
        // The flag bits are read from the metadata registry, so the literal-class
        // query must also register the metadata (keyed by the same type token).
        #expect(
            callees.contains("kk_kclass_register_metadata"),
            "Point::class.isData should register metadata so the flag resolves, got: \(callees)"
        )
    }

    @Test func testClassLiteralIsSealedEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        sealed class Shape
        fun main() {
            println(Shape::class.isSealed)
        }
        """)
        #expect(
            callees.contains("kk_kclass_is_sealed"),
            "Shape::class.isSealed should lower to kk_kclass_is_sealed, got: \(callees)"
        )
    }

    @Test func testClassLiteralIsValueEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        @JvmInline
        value class Wrapped(val v: Int)
        fun main() {
            println(Wrapped::class.isValue)
        }
        """)
        #expect(
            callees.contains("kk_kclass_is_value"),
            "Wrapped::class.isValue should lower to kk_kclass_is_value, got: \(callees)"
        )
    }

    /// The type-kind members (isEnum/isInterface/isObject/isFun) must also be
    /// routed by the KIR dispatch set to the lowerer — without that they would
    /// fall through to a regular call and link-fail with an undefined symbol.
    @Test func testClassLiteralTypeKindMembersEmitRuntimeCalls() throws {
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
            #expect(
                callees.contains(testCase.callee),
                "\(testCase.ref)::class.\(testCase.member) should lower to \(testCase.callee), got: \(callees)"
            )
        }
    }

    // MARK: - Stored KClass<T> variable receiver (regression for the
    // `.classType`-wrapping-KClass receiver guard).

    @Test func testVariableReceiverIsDataEmitsRuntimeCall() throws {
        let callees = try calleesForMain("""
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun main() {
            val k: KClass<Point> = Point::class
            println(k.isData)
        }
        """)
        #expect(
            callees.contains("kk_kclass_is_data"),
            Comment(rawValue: "k.isData on a KClass<Point> variable should lower to kk_kclass_is_data "
                + "(not fall through to an undefined _isData symbol), got: \(callees)")
        )
    }

    @Test func testVariableReceiverStandaloneClassRefRegistersMetadata() throws {
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
        #expect(
            callees.contains("kk_kclass_register_metadata"),
            "Standalone Point::class should register metadata, got: \(callees)"
        )
    }
}
#endif
