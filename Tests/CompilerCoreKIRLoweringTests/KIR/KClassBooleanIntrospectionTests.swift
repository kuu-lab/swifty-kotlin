#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    private func runtimeCall(named callee: String, in ctx: CompilationContext, calls: [KIRCallSite]) -> KIRCallSite? {
        let interned = ctx.interner.intern(callee)
        return calls.first { $0.callee == interned }
    }

    @Test func testClassLiteralIsDataEmitsRuntimeCallAndMetadata() throws {
        let (ctx, calls) = try callsForMain("""
        data class Point(val x: Int)
        fun main() {
            println(Point::class.isData)
        }
        """)
        let flagCall = try #require(
            runtimeCall(named: "__kk_kclass_is_data", in: ctx, calls: calls),
            "Point::class.isData should emit __kk_kclass_is_data, got: \(calls)"
        )
        let creation = try #require(calls.first { $0.callee == KIRRuntimeFunction.kClassCreate.name(in: ctx.interner) })
        let classValue = try #require(creation.result)
        let typeToken = try #require(creation.arguments.first)
        let metadata = try #require(calls.first { $0.callee == KIRRuntimeFunction.kClassMetadata.name(in: ctx.interner) })
        #expect(metadata.arguments.first == typeToken)
        #expect(flagCall.arguments.first == classValue)
        #expect(metadata.index < flagCall.index)
    }

    @Test func testClassLiteralIsSealedEmitsRuntimeCall() throws {
        let (ctx, calls) = try callsForMain("""
        sealed class Shape
        fun main() {
            println(Shape::class.isSealed)
        }
        """)
        #expect(
            runtimeCall(named: "__kk_kclass_is_sealed", in: ctx, calls: calls) != nil,
            "Shape::class.isSealed should emit __kk_kclass_is_sealed, got: \(calls)"
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
        #expect(
            runtimeCall(named: "__kk_kclass_is_value", in: ctx, calls: calls) != nil,
            "Wrapped::class.isValue should emit __kk_kclass_is_value, got: \(calls)"
        )
    }

    @Test func testClassLiteralTypeKindMembersEmitRuntimeCalls() throws {
        let extensionCases: [(decl: String, reference: String, member: String)] = [
            ("enum class Color { RED }", "Color", "isEnum"),
            ("interface Iface", "Iface", "isInterface"),
            ("object Singleton", "Singleton", "isObject"),
        ]
        for testCase in extensionCases {
            let (ctx, calls) = try callsForMain("""
            \(testCase.decl)
            fun main() {
                println(\(testCase.reference)::class.\(testCase.member))
            }
            """)
            let getter = try kClassExtensionGetter(named: testCase.member, in: ctx)
            #expect(
                calls.contains { $0.symbol == getter },
                "\(testCase.reference)::class.\(testCase.member) should resolve to the Kotlin \(testCase.member) getter, got: \(calls)"
            )
        }

        let (ctx, calls) = try callsForMain("""
        fun interface F { fun run() }
        fun main() {
            println(F::class.isFun)
        }
        """)
        #expect(
            runtimeCall(named: "__kk_kclass_is_fun", in: ctx, calls: calls) != nil,
            "F::class.isFun should emit __kk_kclass_is_fun, got: \(calls)"
        )
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
        #expect(
            runtimeCall(named: "__kk_kclass_is_data", in: ctx, calls: calls) != nil,
            Comment(rawValue: "k.isData on a KClass<Point> variable should emit __kk_kclass_is_data "
                + "(not fall through to an undefined _isData symbol), got: \(calls)")
        )
    }

    @Test func testVariableReceiverStandaloneClassRefRegistersMetadata() throws {
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
