#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-REFLECT-067: KClass kind/modifier boolean introspection
/// (`isData` / `isSealed` / `isValue`) lowering.
///
/// KSP-496 moved these to ordinary Kotlin extension properties
/// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt), so `main`'s
/// KIR body now calls the Kotlin getter (e.g. `isData`) directly — the
/// `__kk_kclass_is_*` runtime call happens one level deeper, inside that
/// getter's own KIR function body. These tests assert that `main` resolves
/// to the getter (i.e. does not fall through to an undefined symbol) for
/// both receiver forms:
/// - a compile-time class literal (`Foo::class.isData`), and
/// - a stored `KClass<T>` variable (`val k: KClass<Foo> = Foo::class; k.isData`),
///   which exercises the `.classType`-wrapping-KClass receiver representation.
@Suite
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
            callees.contains("isData"),
            "Point::class.isData should resolve to the Kotlin isData getter, got: \(callees)"
        )
        // The flag bits are read from the metadata registry, so the literal-class
        // query must also register the metadata (keyed by the same type token).
        #expect(
            callees.contains("__kk_kclass_register_metadata"),
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
            callees.contains("isSealed"),
            "Shape::class.isSealed should resolve to the Kotlin isSealed getter, got: \(callees)"
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
            callees.contains("isValue"),
            "Wrapped::class.isValue should resolve to the Kotlin isValue getter, got: \(callees)"
        )
    }

    /// The type-kind members (isEnum/isInterface/isObject/isFun) must also
    /// resolve to their Kotlin getters — without that they would fall
    /// through to a regular call and link-fail with an undefined symbol.
    @Test func testClassLiteralTypeKindMembersEmitRuntimeCalls() throws {
        let cases: [(decl: String, ref: String, member: String)] = [
            ("enum class Color { RED }", "Color", "isEnum"),
            ("interface Iface", "Iface", "isInterface"),
            ("object Singleton", "Singleton", "isObject"),
            ("fun interface F { fun run() }", "F", "isFun"),
        ]
        for testCase in cases {
            let callees = try calleesForMain("""
            \(testCase.decl)
            fun main() {
                println(\(testCase.ref)::class.\(testCase.member))
            }
            """)
            #expect(
                callees.contains(testCase.member),
                "\(testCase.ref)::class.\(testCase.member) should resolve to the Kotlin \(testCase.member) getter, got: \(callees)"
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
            callees.contains("isData"),
            Comment(rawValue: "k.isData on a KClass<Point> variable should resolve to the Kotlin isData getter "
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
            callees.contains("__kk_kclass_register_metadata"),
            "Standalone Point::class should register metadata, got: \(callees)"
        )
    }
}
#endif
