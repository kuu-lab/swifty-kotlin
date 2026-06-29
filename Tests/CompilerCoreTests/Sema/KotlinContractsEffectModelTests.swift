#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - kotlin.contracts effect model edge case tests
//
// STDLIB-CONTRACT-001: Validates that contract { ... } blocks inside inline
// functions are correctly parsed and that the resulting effect models
// (returns/returnsNotNull/callsInPlace) are stored in the SemanticsModels so
// that smart-cast and definite-assignment analysis can rely on them.

@Suite
struct KotlinContractsEffectModelTests {

    // MARK: - returns() implies smart-cast

    /// After `returns() implies (x is String)` the variable `x` should be
    /// narrowed to String, so accessing `.length` must not produce a type
    /// error.
    @Test func testReturnsImpliesIsStringEnablesSmartCast() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun assertIsString(x: Any?) {
            contract {
                returns() implies (x is String)
            }
            if (x !is String) throw IllegalArgumentException()
        }

        fun main() {
            val value: Any? = "hello"
            assertIsString(value)
            println(value.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    /// `returns() implies (x != null)` should narrow x from nullable to non-null.
    @Test func testReturnsImpliesNotNullEnablesSmartCast() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun requireNonNull(x: String?) {
            contract {
                returns() implies (x != null)
            }
            if (x == null) throw IllegalArgumentException()
        }

        fun main() {
            val s: String? = "world"
            requireNonNull(s)
            println(s.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - returnsNotNull()

    /// A function annotated with `returnsNotNull()` should be recognized by
    /// the compiler so that callers can rely on the non-null guarantee.
    @Test func testReturnsNotNullContractIsRecordedOnFunction() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun nonNullResult(input: String?): String {
            contract { returnsNotNull() }
            return input ?: "default"
        }

        fun main() {
            val r = nonNullResult(null)
            println(r.length)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fnSymbol = sema.symbols.allSymbols().first {
                ctx.interner.resolve($0.name) == "nonNullResult"
            }
            #expect(fnSymbol != nil, "nonNullResult should be resolved")
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - callsInPlace(EXACTLY_ONCE) — definite assignment

    /// A `val` assigned inside a lambda passed to `callsInPlace(EXACTLY_ONCE)`
    /// is definitely assigned after the call.  No uninitialized-variable
    /// diagnostic should be emitted.
    @Test func testCallsInPlaceExactlyOnceAllowsDefiniteAssignment() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun runExactlyOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            block()
        }

        fun main() {
            val x: Int
            runExactlyOnce { x = 42 }
            println(x)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    /// The `callsInPlace` effect is stored in the sema model for all four
    /// InvocationKind values.
    @Test func testCallsInPlaceEffectIsStoredForAllInvocationKinds() throws {
        let kinds: [(name: String, kind: InvocationKind)] = [
            ("runAtMostOnce", .atMostOnce),
            ("runAtLeastOnce", .atLeastOnce),
            ("runExactlyOnce", .exactlyOnce),
            ("runUnknown", .unknown),
        ]

        for (fnName, expectedKind) in kinds {
            let source = """
            import kotlin.contracts.*

            @OptIn(ExperimentalContracts::class)
            inline fun \(fnName)(block: () -> Unit) {
                contract { callsInPlace(block, InvocationKind.\(expectedKind.rawValue)) }
                block()
            }

            fun main() { \(fnName) { println("ok") } }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                let sema = try #require(ctx.sema)
                let fnSymbol = sema.symbols.allSymbols().first {
                    ctx.interner.resolve($0.name) == fnName
                }
                guard let sym = fnSymbol else {
                    Issue.record("Symbol \(fnName) not found")
                    return
                }
                let effects = sema.symbols.contractCallsInPlaceEffects(for: sym.id)
                #expect(
                    !effects.isEmpty,
                    "\(fnName): expected callsInPlace effect, got none"
                )
                let hasKind = effects.contains { $0.kind == expectedKind }
                #expect(
                    hasKind,
                    "\(fnName): expected kind \(expectedKind), got \(effects.map(\.kind))"
                )
            }
        }
    }

    // MARK: - callsInPlace(AT_LEAST_ONCE) — at least one call

    /// AT_LEAST_ONCE allows the val to be definitely assigned (the block runs
    /// at least once) but later reads must still be safe.
    @Test func testCallsInPlaceAtLeastOnceAssignmentIsValid() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun runAtLeastOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.AT_LEAST_ONCE) }
            block()
        }

        fun main() {
            var count = 0
            runAtLeastOnce { count++ }
            println(count)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Nested inline functions with contracts

    /// Two layers of inline functions each with their own contracts should
    /// both be accepted without type errors.
    @Test func testNestedInlineFunctionsWithContractsCompile() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun outer(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            inner(block)
        }

        @OptIn(ExperimentalContracts::class)
        inline fun inner(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            block()
        }

        fun main() {
            val result: String
            outer { result = "nested" }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - Contract on infix function

    /// An infix function can carry a contract block; the compiler should
    /// parse it without error and record any declared effect.
    @Test func testContractOnInfixFunctionIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        infix fun String?.mustEqual(expected: String) {
            contract {
                returns() implies (this@mustEqual != null)
            }
            if (this != expected) throw AssertionError()
        }

        fun main() {
            val s: String? = "kotlin"
            s mustEqual "kotlin"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Contract on operator function

    /// An operator function with a contract block should be accepted and the
    /// function should resolve without type errors.
    @Test func testContractOnOperatorFunctionIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        class Box(val value: Int)

        @OptIn(ExperimentalContracts::class)
        operator fun Box?.component1(): Int {
            contract { returnsNotNull() }
            return this?.value ?: 0
        }

        fun main() {
            val b: Box? = Box(7)
            println(b.component1())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - Contract violation: EXACTLY_ONCE block not invoked

    /// Kotlin trusts the contract at compile-time and performs no runtime
    /// check. A function that claims EXACTLY_ONCE but invokes the block zero
    /// times is accepted syntactically; no compile-time error is expected.
    @Test func testExactlyOnceContractWithNoInvocationIsNotACompileError() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun claimsExactlyOnce(block: () -> Unit) {
            contract { callsInPlace(block, InvocationKind.EXACTLY_ONCE) }
            // block intentionally not called — contract violation at runtime,
            // but NOT a compile-time error in Kotlin's trusted-contract model.
        }

        fun main() {
            claimsExactlyOnce { println("maybe") }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // The compiler trusts the declared contract; no error should be
            // emitted at compile time for the violation.
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - returns(value) implies condition

    /// `returns(true) implies (condition)` should allow the compiler to narrow
    /// the subject of `condition` after a call where the boolean result is true.
    @Test func testReturnsTrueImpliesConditionContractIsAccepted() throws {
        let source = """
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class)
        inline fun isNonNull(x: String?): Boolean {
            contract {
                returns(true) implies (x != null)
            }
            return x != null
        }

        fun main() {
            val s: String? = "contracts"
            if (isNonNull(s)) {
                println(s.length)
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - ContractBuilder stubs resolve in symbol table

    /// The compiler must synthesize the full `kotlin.contracts` package with
    /// ContractBuilder, Effect, CallsInPlace, SimpleEffect, Returns, ReturnsNotNull, ConditionalEffect,
    /// HoldsIn, and InvocationKind so that user code importing `kotlin.contracts.*` can
    /// resolve these names.
    @Test func testContractBuilderAndInvocationKindSymbolsExist() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        #expect(
            sema.symbols.lookup(fqName: contractsFQName) != nil,
            "kotlin.contracts package should be synthesized"
        )

        let expectedSymbols: [(name: String, kind: SymbolKind)] = [
            ("ContractBuilder", .class),
            ("Effect", .interface),
            ("CallsInPlace", .interface),
            ("SimpleEffect", .interface),
            ("Returns", .interface),
            ("ReturnsNotNull", .interface),
            ("ConditionalEffect", .interface),
            ("HoldsIn", .interface),
            ("InvocationKind", .enumClass),
        ]

        for expected in expectedSymbols {
            let fqName = contractsFQName + [ctx.interner.intern(expected.name)]
            let symbol = try #require(
                sema.symbols.lookup(fqName: fqName),
                "\(expected.name) should be synthesized inside kotlin.contracts"
            )
            #expect(sema.symbols.symbol(symbol)?.kind == expected.kind)
        }
    }

    @Test func testCallsInPlaceInterfaceAndBuilderSurfaceAreRegistered() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        let effectSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("Effect")])
        )
        let callsInPlaceSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("CallsInPlace")])
        )
        #expect(sema.symbols.symbol(callsInPlaceSymbol)?.kind == .interface)
        let callsInPlaceExtendsEffect = sema.symbols.directSupertypes(for: callsInPlaceSymbol).contains(effectSymbol)
        #expect(
            callsInPlaceExtendsEffect,
            "CallsInPlace must extend Effect"
        )
        let callsInPlaceAnnotations = sema.symbols.annotations(for: callsInPlaceSymbol)
        let callsInPlaceHasExperimentalContracts = callsInPlaceAnnotations.contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
        }
        #expect(
            callsInPlaceHasExperimentalContracts,
            "CallsInPlace should carry ExperimentalContracts"
        )

        let builderFQName = contractsFQName + [ctx.interner.intern("ContractBuilder")]
        let builderSymbol = try #require(sema.symbols.lookup(fqName: builderFQName))
        let builderType = sema.types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let callsInPlaceType = sema.types.make(.classType(ClassType(
            classSymbol: callsInPlaceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let callsInPlaceOverloads = sema.symbols.lookupAll(
            fqName: builderFQName + [ctx.interner.intern("callsInPlace")]
        )
        let hasOneParamOverload = callsInPlaceOverloads.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == builderType
                && signature.parameterTypes.count == 1
                && signature.returnType == callsInPlaceType
        }
        #expect(
            hasOneParamOverload,
            "ContractBuilder.callsInPlace(lambda) should return CallsInPlace"
        )
        let hasTwoParamOverload = callsInPlaceOverloads.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == builderType
                && signature.parameterTypes.count == 2
                && signature.returnType == callsInPlaceType
        }
        #expect(
            hasTwoParamOverload,
            "ContractBuilder.callsInPlace(lambda, kind) should return CallsInPlace"
        )
    }

    @Test func testReturnsInterfaceAndBuilderSurfaceAreRegistered() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        let simpleEffectSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("SimpleEffect")])
        )
        let returnsSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("Returns")])
        )
        #expect(sema.symbols.symbol(returnsSymbol)?.kind == .interface)
        let returnsExtendsSimpleEffect = sema.symbols.directSupertypes(for: returnsSymbol).contains(simpleEffectSymbol)
        #expect(
            returnsExtendsSimpleEffect,
            "Returns must extend SimpleEffect"
        )
        let returnsAnnotations = sema.symbols.annotations(for: returnsSymbol)
        let returnsHasExperimentalContracts = returnsAnnotations.contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
        }
        #expect(
            returnsHasExperimentalContracts,
            "Returns should carry ExperimentalContracts"
        )

        let builderFQName = contractsFQName + [ctx.interner.intern("ContractBuilder")]
        let builderSymbol = try #require(sema.symbols.lookup(fqName: builderFQName))
        let builderType = sema.types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnsType = sema.types.make(.classType(ClassType(
            classSymbol: returnsSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnsOverloads = sema.symbols.lookupAll(
            fqName: builderFQName + [ctx.interner.intern("returns")]
        )
        let hasNoParamReturns = returnsOverloads.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == builderType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnsType
        }
        #expect(
            hasNoParamReturns,
            "ContractBuilder.returns() should return Returns"
        )
        let hasValueParamReturns = returnsOverloads.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == builderType
                && signature.parameterTypes == [sema.types.booleanType]
                && signature.returnType == returnsType
        }
        #expect(
            hasValueParamReturns,
            "ContractBuilder.returns(value) should return Returns"
        )
    }

    @Test func testReturnsNotNullInterfaceAndBuilderSurfaceAreRegistered() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        let simpleEffectSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("SimpleEffect")])
        )
        let returnsNotNullSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("ReturnsNotNull")])
        )
        #expect(sema.symbols.symbol(returnsNotNullSymbol)?.kind == .interface)
        let returnsNotNullExtendsSimpleEffect = sema.symbols.directSupertypes(for: returnsNotNullSymbol).contains(simpleEffectSymbol)
        #expect(
            returnsNotNullExtendsSimpleEffect,
            "ReturnsNotNull must extend SimpleEffect"
        )
        let returnsNotNullAnnotations = sema.symbols.annotations(for: returnsNotNullSymbol)
        let returnsNotNullHasExperimentalContracts = returnsNotNullAnnotations.contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
        }
        #expect(
            returnsNotNullHasExperimentalContracts,
            "ReturnsNotNull should carry ExperimentalContracts"
        )

        let builderFQName = contractsFQName + [ctx.interner.intern("ContractBuilder")]
        let builderSymbol = try #require(sema.symbols.lookup(fqName: builderFQName))
        let builderType = sema.types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnsNotNullType = sema.types.make(.classType(ClassType(
            classSymbol: returnsNotNullSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnsNotNullOverloads = sema.symbols.lookupAll(
            fqName: builderFQName + [ctx.interner.intern("returnsNotNull")]
        )
        let hasReturnsNotNull = returnsNotNullOverloads.contains { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
            return signature.receiverType == builderType
                && signature.parameterTypes.isEmpty
                && signature.returnType == returnsNotNullType
        }
        #expect(
            hasReturnsNotNull,
            "ContractBuilder.returnsNotNull() should return ReturnsNotNull"
        )
    }

    @Test func testHoldsInInterfaceAndBuilderSurfaceAreRegistered() throws {
        let source = """
        import kotlin.contracts.*

        fun noop() {}
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let sema = try #require(ctx.sema)

        let contractsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
        ]
        let effectSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("Effect")])
        )
        let holdsInSymbol = try #require(
            sema.symbols.lookup(fqName: contractsFQName + [ctx.interner.intern("HoldsIn")])
        )
        #expect(sema.symbols.symbol(holdsInSymbol)?.kind == .interface)
        let holdsInExtendsEffect = sema.symbols.directSupertypes(for: holdsInSymbol).contains(effectSymbol)
        #expect(
            holdsInExtendsEffect,
            "HoldsIn must extend Effect"
        )
        let holdsInAnnotations = sema.symbols.annotations(for: holdsInSymbol)
        let holdsInHasExperimentalContracts = holdsInAnnotations.contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
        }
        #expect(
            holdsInHasExperimentalContracts,
            "HoldsIn should carry ExperimentalContracts"
        )
        let holdsInHasExperimentalExtended = holdsInAnnotations.contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts"
        }
        #expect(
            holdsInHasExperimentalExtended,
            "HoldsIn should carry ExperimentalExtendedContracts"
        )

        let builderFQName = contractsFQName + [ctx.interner.intern("ContractBuilder")]
        let builderSymbol = try #require(sema.symbols.lookup(fqName: builderFQName))
        let builderType = sema.types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let holdsInType = sema.types.make(.classType(ClassType(
            classSymbol: holdsInSymbol,
            args: [],
            nullability: .nonNull
        )))
        let holdsInFunction = try #require(
            sema.symbols.lookupAll(fqName: builderFQName + [ctx.interner.intern("holdsIn")]).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                return signature.receiverType == builderType
                    && signature.parameterTypes.first == sema.types.booleanType
                    && signature.returnType == holdsInType
            },
            "ContractBuilder.holdsIn should be synthesized"
        )
        let holdsInFnHasExperimentalExtended = sema.symbols.annotations(for: holdsInFunction).contains {
            $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts"
        }
        #expect(
            holdsInFnHasExperimentalExtended,
            "ContractBuilder.holdsIn should carry ExperimentalExtendedContracts"
        )
    }

    @Test func testHoldsInBuilderSurfaceResolvesInSourceWithOptIn() throws {
        let source = """
        import kotlin.OptIn
        import kotlin.contracts.*

        @OptIn(ExperimentalContracts::class, ExperimentalExtendedContracts::class)
        inline fun guarded(flag: Boolean, block: () -> Unit) {
            contract { holdsIn(flag, block) }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected holdsIn contract surface to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }
}
#endif
