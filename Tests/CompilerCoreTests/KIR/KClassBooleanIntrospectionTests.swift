#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-496 moved these to ordinary Kotlin extension properties
/// (Sources/CompilerCore/Stdlib/kotlin/reflect/KClasses.kt), so `main`'s
/// KIR body now calls the Kotlin getter (e.g. `isData`) directly — the
/// `__kk_kclass_is_*` runtime call happens one level deeper, inside that
/// getter's own KIR function body. These tests assert that `main` resolves
/// to the getter (i.e. does not fall through to an undefined symbol) for
/// both receiver forms:
@Suite
struct KClassBooleanIntrospectionTests {

    private func callsForMain(_ source: String) throws -> (CompilationContext, [KIRCallSite]) {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected source to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        return (ctx, kirCalls(in: body))
    }

    @Test func testClassLiteralIsDataEmitsRuntimeCallAndMetadata() throws {
        let (ctx, calls) = try callsForMain("""
        data class Point(val x: Int)
        fun main() {
            println(Point::class.isData)
        }
        """)
        let getter = try kClassExtensionGetter(named: "isData", in: ctx)
        let getterCall = try #require(calls.first { $0.symbol == getter })
        let creation = try #require(calls.first { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) })
        let classValue = try #require(creation.result)
        let typeToken = try #require(creation.arguments.first)
        // The flag bits are read from the metadata registry, so the literal-class
        // query must also register the metadata (keyed by the same type token).
        let metadata = try #require(calls.first { $0.callee == KIRRuntimeFunction.kClassMetadata.name(in: ctx.interner) })
        #expect(metadata.arguments.first == typeToken)
        #expect(getterCall.arguments.first == classValue)
        #expect(metadata.index < getterCall.index)
    }

    @Test func testClassLiteralIsSealedEmitsRuntimeCall() throws {
        let (ctx, calls) = try callsForMain("""
        sealed class Shape
        fun main() {
            println(Shape::class.isSealed)
        }
        """)
        let getter = try kClassExtensionGetter(named: "isSealed", in: ctx)
        #expect(
            calls.contains { $0.symbol == getter },
            "Shape::class.isSealed should resolve to the Kotlin isSealed getter, got: \(calls)"
        )
    }

    @Test func testClassLiteralIsValueEmitsRuntimeCall() throws {
        let (ctx, calls) = try callsForMain("""
        @JvmInline
        value class Wrapped(val v: Int)
        fun main() {
            println(Wrapped::class.isValue)
        }
        """)
        let getter = try kClassExtensionGetter(named: "isValue", in: ctx)
        #expect(
            calls.contains { $0.symbol == getter },
            "Wrapped::class.isValue should resolve to the Kotlin isValue getter, got: \(calls)"
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
            let (ctx, calls) = try callsForMain("""
            \(testCase.decl)
            fun main() {
                println(\(testCase.ref)::class.\(testCase.member))
            }
            """)
            let getter = try kClassExtensionGetter(named: testCase.member, in: ctx)
            #expect(
                calls.contains { $0.symbol == getter },
                "\(testCase.ref)::class.\(testCase.member) should resolve to the Kotlin \(testCase.member) getter, got: \(calls)"
            )
        }
    }

    @Test func testVariableReceiverIsDataEmitsRuntimeCall() throws {
        let (ctx, calls) = try callsForMain("""
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun main() {
            val k: KClass<Point> = Point::class
            println(k.isData)
        }
        """)
        let getter = try kClassExtensionGetter(named: "isData", in: ctx)
        #expect(
            calls.contains { $0.symbol == getter },
            Comment(rawValue: "k.isData on a KClass<Point> variable should resolve to the Kotlin isData getter "
                + "(not fall through to an undefined _isData symbol), got: \(calls)")
        )
    }

    @Test func testVariableReceiverStandaloneClassRefRegistersMetadata() throws {
        // A standalone `T::class` stored in a variable must register metadata so a
        // later `k.isData` resolves the flag even when the class is never built.
        let (ctx, calls) = try callsForMain("""
        import kotlin.reflect.KClass
        data class Point(val x: Int)
        fun main() {
            val k: KClass<Point> = Point::class
            println(k.isData)
        }
        """)
        #expect(
            calls.contains { $0.callee == KIRRuntimeFunction.kClassMetadata.name(in: ctx.interner) },
            "Standalone Point::class should register metadata, got: \(calls)"
        )
    }
}
#endif
