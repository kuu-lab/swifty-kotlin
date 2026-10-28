#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenCallableReferenceInvocationTests {
    @Test
    func immediatelyInvokesCallableReferenceSelectedFromWhenBranches() throws {
        let ctx = makeContextFromSource("""
        fun decodeValue(value: String): Any {
            return when (value[0]) {
                'F' -> String::toFloat
                'I' -> String::toInt
                else -> throw IllegalArgumentException("x")
            }(value.substring(2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func overloadedReferencesUseImmediateInvocationArguments() throws {
        let ctx = makeContextFromSource("""
        fun parse(value: Int): String = "int"
        fun parse(value: String): String = "string"
        fun other(value: String): String = value
        fun useWhen(): String = (when (true) {
            true -> ::parse
            false -> ::other
        })("42")
        fun useIf(): String = (if (true) ::parse else ::other)("42")
        fun useSmartCast(value: Any): String = (when (value as String) {
            "42" -> ::parse
            else -> ::other
        })(value)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func branchContextPreservesNullableReturnsAndLiteralTypes() throws {
        let ctx = makeContextFromSource("""
        fun nullableChoice(value: Int): String? = null
        fun nullableChoice(value: String): String? = value
        fun nullableOther(value: Int): String? = null
        fun narrow(value: Byte): String = "byte"
        fun narrow(value: String): String = value
        fun narrowOther(value: Byte): String = "other"
        fun multi(value: Int): String = "int"
        fun multi(value: String): String = value
        fun anyOther(value: Any): String = "any"
        fun intOther(value: Int): String = "int"
        fun inferredNullable(flag: Boolean): Int {
            val result = (if (flag) ::nullableChoice else ::nullableOther)(1)
            return result?.length ?: 0
        }
        fun narrowLiteral(flag: Boolean): Int {
            val result = (if (flag) ::narrow else ::narrowOther)(127)
            return result.length
        }
        fun multiAnyFirst(flag: Int) = (when (flag) { 0 -> ::multi; 1 -> ::anyOther; else -> ::intOther })(1)
        fun multiIntFirst(flag: Int) = (when (flag) { 0 -> ::multi; 1 -> ::intOther; else -> ::anyOther })(1)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func branchContextDoesNotResolveWithoutCompatibleAnchor() throws {
        let ctx = makeContextFromSource("""
        fun maybe(value: Int): String = "int"
        fun maybe(value: String): String = value
        fun fixedAny(value: Any): String = "any"
        fun fixedInt(value: Int): String = "int"
        fun maybeByte(value: Byte): String = "byte"
        fun maybeByte(value: String): String = value
        fun fixedByte(value: Byte): String = "byte"
        fun rejectBothIf(flag: Boolean) = (if (flag) ::maybe else ::maybe)(1)
        fun rejectBothWhen(flag: Boolean) = (when (flag) { true -> ::maybe; false -> ::maybe })(1)
        fun rejectThrow(flag: Boolean) = (if (flag) ::maybe else throw IllegalStateException())(1)
        fun rejectAny(flag: Boolean) = (if (flag) ::maybe else ::fixedAny)(1)
        fun rejectByteOverflow(flag: Boolean) = (if (flag) ::maybeByte else ::fixedByte)(128)
        fun rejectIntVariable(flag: Boolean, value: Int) = (if (flag) ::maybeByte else ::fixedByte)(value)
        fun rejectCondition() = (if (missing) ::maybe else ::fixedInt)(1)
        fun rejectBranch() = (if (true) ::maybe else ::absent)(1)
        fun rejectArgument(flag: Boolean) = (if (flag) ::maybe else ::fixedInt)(missingArg)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let errorLines = Set(errors.compactMap { diagnostic in
            diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
        })
        for line in 8...16 {
            #expect(errorLines.contains(line), "Missing error on line \(line): \(errors)")
        }
    }

    @Test(arguments: [
        """
        fun parse(value: Int): String = "int"
        fun parse(value: String): String = "string"
        fun test() { val f = ::parse }
        """,
        """
        fun parse(value: String): String = value
        fun parse(value: Int, extra: Int): String = "int"
        fun other(value: String): String = value
        fun test() = (when (true) { true -> ::parse; false -> ::other })(42)
        """,
        """
        fun test() = (if (true) ({ x -> x + 1 }) else ({ x -> x + 2 }))(42)
        """,
    ])
    func stillRejectsInvalidControls(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected an error for: \(source)")
    }
}
#endif
