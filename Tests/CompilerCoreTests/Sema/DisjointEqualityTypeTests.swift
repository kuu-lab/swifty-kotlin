@testable import CompilerCore
import Testing

@Suite
struct DisjointEqualityTypeTests {
    @Test func receiverFunctionCallResultUsesReturnTypeInEquality() throws {
        try withTemporaryFile(contents: """
        fun box(): String {
            val f: Int.(Int) -> String = { "15" }
            return if ("15" == 5.f(10)) "OK" else "FAIL"
        }

        fun smartCasted(value: Any): Boolean {
            if (value is Int) return value == "text"
            return false
        }

        fun directComparison(value: Int) = value == "text"
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1 && errors.first?.code == "KSWIFTK-SEMA-0002",
                "Only the unrelated direct Int/String comparison should be rejected: \(errors)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let invocationIndex = try #require(ast.arena.exprs.enumerated().first { _, expr in
                guard case let .memberCall(_, name, _, args, _) = expr,
                      args.count == 1
                else { return false }
                return ctx.interner.resolve(name) == "f"
            }?.offset)
            let invocation = ExprID(rawValue: Int32(invocationIndex))
            #expect(sema.bindings.exprType(for: invocation) == sema.types.stringType)
            #expect(sema.bindings.callableValueCallBinding(for: invocation) != nil)
            #expect(sema.bindings.identifierSymbol(for: invocation) != nil,
                "Capture analysis must retain the receiver-function value's symbol on its call")
        }
    }

    @Test func matchesKotlinBuiltinEqualityCompatibility() throws {
        let sources = [
            """
            package invalid
            class Custom
            fun compareRange(range: LongRange) = range == "x"
            fun nullable(first: String?, second: Int?) = first == second
            fun numeric(first: Int, second: Long) = first != second
            fun nullableNumeric(first: Long?, second: Int?) = first == second
            fun custom(first: Custom, second: String) = first == second
            fun explicitCast(value: Any, text: String) = (value as Int) == text
            """,
            """
            package valid
            class First
            class Second
            fun classes(first: First, second: Second) = first == second
            fun nullableClasses(first: First?, second: Second?) = first != second
            open class Base
            class Derived : Base()
            fun related(base: Base, derived: Derived) = base == derived
            fun erased(any: Any, text: String) = any == text
            fun nullable(any: Any?, text: String?) = any == text
            fun same(first: String?, second: String?) = first == second
            fun nullLiteral(text: String?) = text == null
            fun nullLeft(text: String?) = null == text
            fun nullableRelated(base: Base?, derived: Derived?) = base == derived
            interface Marker
            class Plain
            fun interfaceFinal(marker: Marker, plain: Plain) = marker == plain
            class Other
            fun openFinal(base: Base, other: Other) = base == other
            fun ranges(first: IntRange, second: LongRange) = first == second
            fun rangeExpression(range: LongRange): Boolean {
                val same = 2L..11L
                return range == same
            }
            fun <T> generic(value: T, number: Int) = value == number
            fun <T : Any> nonNullGeneric(value: T, number: Int) = value == number
            fun comparable(text: String, other: Comparable<Int>) = text == other
            fun comparableNumber(number: Int, other: Comparable<String>) = number == other
            fun narrowed(value: Any, text: String): Boolean {
                if (value is Int) return value == text
                return false
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let invalid = diagnosticsForPath(paths[0], in: ctx)
            #expect(invalid.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 6)
            let valid = diagnosticsForPath(paths[1], in: ctx)
            #expect(valid.isEmpty, "Compatible equality operands should remain accepted: \(valid)")
        }
    }

    @Test func zeroArgumentCollectionFactoryRequiresInferenceEvidence() throws {
        let source = """
        fun badEmptyList(values: List<Int>) = values == emptyList()
        fun badEmptyListOnLeft(values: List<Int>) = emptyList() == values
        fun badListOf(values: List<Int>) = values == listOf()
        fun badEmptySet(values: Set<Int>) = values == emptySet()
        fun badMutableListOf(values: MutableList<Int>) = values == mutableListOf()
        fun badEmptyMap(values: Map<Int, String>) = values == emptyMap()
        fun badNotEqual(values: List<Int>) = values != emptyList()
        fun badIdentity(values: List<Int>) = values === emptyList()
        fun badIdentityOnLeft(values: List<Int>) = emptyList() === values
        fun explicit(values: List<Int>) = values == emptyList<Int>()
        fun contextualList(): List<Int> = emptyList()
        fun contextualSet(): Set<Int> = emptySet()
        fun contextualMap(): Map<Int, String> = emptyMap()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 9, "Only untyped equality operands should be rejected: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-INFER" }, "Got: \(errors)")
    }

    @Test func lambdaEqualityUsesParameterTypesBeforeSmartCasting() throws {
        let sources = [
            """
            package valid
            fun lambdas() {
                val explicitEqual: (Any) -> Boolean = { value ->
                    if (value is Int) value == "a" else false
                }
                val explicitNotEqual: (Any) -> Boolean = { value ->
                    if (value is Int) "a" != value else false
                }
                val implicitEqual: (Any) -> Boolean = {
                    if (it is Int) it == "a" else false
                }
                val implicitNotEqual: (Any) -> Boolean = {
                    if (it is Int) "a" != it else false
                }
            }
            """,
            """
            package invalid
            fun lambdas() {
                val explicit: (Int) -> Boolean = { value -> value == "a" }
                val implicit: (Int) -> Boolean = { "a" != it }
                val annotated = { value: Int -> value == "a" }
                val cast: (Any) -> Boolean = { (it as Int) != "a" }
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let valid = diagnosticsForPath(paths[0], in: ctx)
            #expect(valid.isEmpty, "Smart-cast lambda parameters should use their declared types: \(valid)")
            let invalid = diagnosticsForPath(paths[1], in: ctx)
            #expect(invalid.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 4)
        }
    }

    @Test func rangeOperandsUseSourceLevelTypes() throws {
        let sources = [
            """
            package valid
            fun longRanges(): Boolean {
                val constructed = LongRange(2L, 11L)
                val literal = 2L..11L
                return constructed == literal && literal == constructed &&
                    constructed != (2L..12L) && literal == (2L..11L)
            }
            fun intRange(range: IntRange) = range == (1..2)
            fun charRange(range: CharRange) = range == ('a'..'z')
            fun uintRange(range: UIntRange) = range == (1u..2u)
            fun ulongRange(range: ULongRange) = range == (1uL..2uL)
            fun floatingRange(range: ClosedFloatingPointRange<Double>): Boolean {
                val literal = 1.0..2.0
                return range == literal && literal == range
            }
            """,
            """
            package invalid
            fun longRange() = (1L..2L) == 1L
            fun intRange() = (1..2) == 1
            fun charRange() = ('a'..'z') == 'a'
            fun uintRange() = (1u..2u) == 1u
            fun ulongRange() = (1uL..2uL) == 1uL
            fun floatingRange() = (1.0..2.0) == 1.0
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let valid = diagnosticsForPath(paths[0], in: ctx)
            #expect(valid.isEmpty, "Range operands should use their source-level types: \(valid)")
            let invalid = diagnosticsForPath(paths[1], in: ctx)
            #expect(invalid.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 6)
        }
    }
}
