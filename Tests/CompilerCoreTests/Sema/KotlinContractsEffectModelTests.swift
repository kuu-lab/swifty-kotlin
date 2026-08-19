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

    /// `returns() implies (x != null)` should narrow x from nullable to non-null.

    // MARK: - returnsNotNull()

    /// A function annotated with `returnsNotNull()` should be recognized by
    /// the compiler so that callers can rely on the non-null guarantee.

    // MARK: - callsInPlace(EXACTLY_ONCE) — definite assignment

    /// A `val` assigned inside a lambda passed to `callsInPlace(EXACTLY_ONCE)`
    /// is definitely assigned after the call.  No uninitialized-variable
    /// diagnostic should be emitted.

    /// The `callsInPlace` effect is stored in the sema model for all four
    /// InvocationKind values.

    // MARK: - callsInPlace(AT_LEAST_ONCE) — at least one call

    /// AT_LEAST_ONCE allows the val to be definitely assigned (the block runs
    /// at least once) but later reads must still be safe.

    // MARK: - Nested inline functions with contracts

    /// Two layers of inline functions each with their own contracts should
    /// both be accepted without type errors.

    // MARK: - Contract on infix function

    /// An infix function can carry a contract block; the compiler should
    /// parse it without error and record any declared effect.

    // MARK: - Contract on operator function

    /// An operator function with a contract block should be accepted and the
    /// function should resolve without type errors.

    // MARK: - Contract violation: EXACTLY_ONCE block not invoked

    /// Kotlin trusts the contract at compile-time and performs no runtime
    /// check. A function that claims EXACTLY_ONCE but invokes the block zero
    /// times is accepted syntactically; no compile-time error is expected.

    // MARK: - returns(value) implies condition

    /// `returns(true) implies (condition)` should allow the compiler to narrow
    /// the subject of `condition` after a call where the boolean result is true.

    // MARK: - ContractBuilder stubs resolve in symbol table

    /// The compiler must synthesize the full `kotlin.contracts` package with
    /// ContractBuilder, Effect, CallsInPlace, SimpleEffect, Returns, ReturnsNotNull, ConditionalEffect,
    /// HoldsIn, and InvocationKind so that user code importing `kotlin.contracts.*` can
    /// resolve these names.

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testReturnsImpliesIsStringEnablesSmartCast
            """
            package sample0

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

            """,
            // testReturnsImpliesNotNullEnablesSmartCast
            """
            package sample1

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

            """,
            // testReturnsNotNullContractIsRecordedOnFunction
            """
            package sample2

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

            """,
            // testCallsInPlaceExactlyOnceAllowsDefiniteAssignment
            """
            package sample3

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

            """,
            // testCallsInPlaceAtLeastOnceAssignmentIsValid
            """
            package sample4

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

            """,
            // testNestedInlineFunctionsWithContractsCompile
            """
            package sample5

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

            """,
            // testContractOnInfixFunctionIsAccepted
            """
            package sample6

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

            """,
            // testContractOnOperatorFunctionIsAccepted
            """
            package sample7

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

            """,
            // testExactlyOnceContractWithNoInvocationIsNotACompileError
            """
            package sample8

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

            """,
            // testReturnsTrueImpliesConditionContractIsAccepted
            """
            package sample9

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

            """,
            // testContractBuilderAndInvocationKindSymbolsExist
            """
            package sample10

                    import kotlin.contracts.*

                    fun noop() {}

            """,
            // testCallsInPlaceInterfaceAndBuilderSurfaceAreRegistered
            """
            package sample11

                    import kotlin.contracts.*

                    fun noop() {}

            """,
            // testReturnsInterfaceAndBuilderSurfaceAreRegistered
            """
            package sample12

                    import kotlin.contracts.*

                    fun noop() {}

            """,
            // testReturnsNotNullInterfaceAndBuilderSurfaceAreRegistered
            """
            package sample13

                    import kotlin.contracts.*

                    fun noop() {}

            """,
            // testHoldsInInterfaceAndBuilderSurfaceAreRegistered
            """
            package sample14

                    import kotlin.contracts.*

                    fun noop() {}

            """,
            // testHoldsInBuilderSurfaceResolvesInSourceWithOptIn
            """
            package sample15

                    import kotlin.OptIn
                    import kotlin.contracts.*

                    @OptIn(ExperimentalContracts::class, ExperimentalExtendedContracts::class)
                    inline fun guarded(flag: Boolean, block: () -> Unit) {
                        contract { flag.holdsIn(block) }
                    }

            """,
            // testNonInlineContractPreservesNullableArgumentSmartCast
            """
            package sample16

                    import kotlin.contracts.*

                    @OptIn(ExperimentalContracts::class)
                    fun assertNotNull(value: Any?) {
                        contract {
                            returns() implies (value != null)
                        }
                        if (value == null) throw IllegalArgumentException("null")
                    }

                    fun main() {
                        val value: String? = "source-backed"
                        assertNotNull(value)
                        println(value.length)
                    }

            """,
            // testNonNullContractDoesNotNarrowVariablesInsideBooleanArgument
            """
            package sample17

                    import kotlin.contracts.*

                    @OptIn(ExperimentalContracts::class)
                    fun assertNotNull(value: Any?) {
                        contract {
                            returns() implies (value != null)
                        }
                        if (value == null) throw IllegalArgumentException("null")
                    }

                    fun nullableText(): String? = null

                    fun main() {
                        val value: String? = nullableText()
                        assertNotNull(value != null)
                        println(value.length)
                    }

            """,
            // testNonexistentBooleanImpliesReturnsNotNullIsRejected
            """
            package sample18

                    import kotlin.contracts.*

                    @OptIn(ExperimentalContracts::class, ExperimentalExtendedContracts::class)
                    fun invalidContract() {
                        contract { true implies returnsNotNull() }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testReturnsImpliesIsStringEnablesSmartCast ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample0Diagnostics)

            }

            // === testReturnsImpliesNotNullEnablesSmartCast ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)

            }

            // === testReturnsNotNullContractIsRecordedOnFunction ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let fnSymbol = sema.symbols.allSymbols().first {
                    interner.resolve($0.name) == "nonNullResult"
                }
                #expect(fnSymbol != nil, "nonNullResult should be resolved")
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample2Diagnostics)

            }

            // === testCallsInPlaceExactlyOnceAllowsDefiniteAssignment ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample3Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample3Diagnostics)

            }

            // === testCallsInPlaceAtLeastOnceAssignmentIsValid ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample4Diagnostics)

            }

            // === testNestedInlineFunctionsWithContractsCompile ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample5Diagnostics)

            }

            // === testContractOnInfixFunctionIsAccepted ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample6Diagnostics)

            }

            // === testContractOnOperatorFunctionIsAccepted ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample7Diagnostics)

            }

            // === testExactlyOnceContractWithNoInvocationIsNotACompileError ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                // The compiler trusts the declared contract; no error should be
                // emitted at compile time for the violation.
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample8Diagnostics)

            }

            // === testReturnsTrueImpliesConditionContractIsAccepted ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample9Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample9Diagnostics)

            }

            // === testContractBuilderAndInvocationKindSymbolsExist ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let contractsFQName = [
                    interner.intern("kotlin"),
                    interner.intern("contracts"),
                ]
                #expect(
                    sema.symbols.lookup(fqName: contractsFQName) != nil,
                    "kotlin.contracts package should be synthesized"
                )

                let expectedSymbols: [(name: String, kind: SymbolKind)] = [
                    ("ContractBuilder", .interface),
                    ("ContractEffect", .interface),
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
                    let fqName = contractsFQName + [interner.intern(expected.name)]
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: fqName),
                        "\(expected.name) should be source-backed inside kotlin.contracts"
                    )
                    #expect(sema.symbols.symbol(symbol)?.kind == expected.kind)
                    #expect(
                        !(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) ?? true),
                        "\(expected.name) must not be synthetic"
                    )
                    #expect(
                        sema.symbols.symbol(symbol)?.declSite != nil,
                        "\(expected.name) must have a bundled source declaration"
                    )
                    if let fileID = sema.symbols.sourceFileID(for: symbol) {
                        #expect(
                            ctx.sourceManager.path(of: fileID).hasPrefix("__bundled_kotlin/contracts/"),
                            "\(expected.name) must come from bundled kotlin/contracts source"
                        )
                    } else {
                        #expect(Bool(false), "\(expected.name) must have a bundled source file")
                    }
                    #expect(
                        sema.symbols.externalLinkName(for: symbol) == nil,
                        "\(expected.name) must not have an external link"
                    )
                }

                let markerDeclarations = [
                    "ExperimentalContracts",
                    "ExperimentalExtendedContracts",
                ]
                for markerName in markerDeclarations {
                    let markerSymbol = try #require(
                        sema.symbols.lookup(
                            fqName: contractsFQName + [interner.intern(markerName)]
                        ),
                        "\(markerName) should be source-backed inside kotlin.contracts"
                    )
                    let markerAnnotations = sema.symbols.annotations(for: markerSymbol)
                    #expect(
                        markerAnnotations.contains {
                            $0.annotationFQName.hasSuffix("RequiresOptIn")
                        },
                        "\(markerName) should carry RequiresOptIn metadata"
                    )
                    #expect(
                        markerAnnotations.contains {
                            $0.annotationFQName.hasSuffix("MustBeDocumented")
                        },
                        "\(markerName) should carry MustBeDocumented metadata"
                    )
                    #expect(
                        markerAnnotations.contains {
                            $0.annotationFQName.hasSuffix("Retention")
                                && $0.arguments.contains {
                                    $0.hasSuffix("AnnotationRetention.BINARY")
                                }
                        },
                        "\(markerName) should carry BINARY retention metadata"
                    )
                }

            }

            // === testCallsInPlaceInterfaceAndBuilderSurfaceAreRegistered ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let contractsFQName = [
                    interner.intern("kotlin"),
                    interner.intern("contracts"),
                ]
                let effectSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("Effect")])
                )
                let callsInPlaceSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("CallsInPlace")])
                )
                #expect(sema.symbols.symbol(callsInPlaceSymbol)?.kind == .interface)
                let callsInPlaceExtendsEffect = sema.symbols.directSupertypes(for: callsInPlaceSymbol).contains(effectSymbol)
                #expect(
                    callsInPlaceExtendsEffect,
                    "CallsInPlace must extend Effect"
                )
                let callsInPlaceAnnotations = sema.symbols.annotations(for: callsInPlaceSymbol)
                let callsInPlaceHasExperimentalContracts = callsInPlaceAnnotations.contains {
                    $0.annotationFQName == "ExperimentalContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
                }
                #expect(
                    callsInPlaceHasExperimentalContracts,
                    "CallsInPlace should carry ExperimentalContracts"
                )

                let builderFQName = contractsFQName + [interner.intern("ContractBuilder")]
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
                    fqName: builderFQName + [interner.intern("callsInPlace")]
                )
                let hasDefaultKindParameter = callsInPlaceOverloads.contains { symbol in
                    guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                    return signature.receiverType == builderType
                        && signature.parameterTypes.count == 2
                        && signature.returnType == callsInPlaceType
                        && signature.valueParameterHasDefaultValues == [false, true]
                }
                #expect(
                    hasDefaultKindParameter,
                    "ContractBuilder.callsInPlace(lambda, kind = InvocationKind.UNKNOWN) should return CallsInPlace"
                )

            }

            // === testReturnsInterfaceAndBuilderSurfaceAreRegistered ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let contractsFQName = [
                    interner.intern("kotlin"),
                    interner.intern("contracts"),
                ]
                let simpleEffectSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("SimpleEffect")])
                )
                let returnsSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("Returns")])
                )
                #expect(sema.symbols.symbol(returnsSymbol)?.kind == .interface)
                let returnsExtendsSimpleEffect = sema.symbols.directSupertypes(for: returnsSymbol).contains(simpleEffectSymbol)
                #expect(
                    returnsExtendsSimpleEffect,
                    "Returns must extend SimpleEffect"
                )
                let returnsAnnotations = sema.symbols.annotations(for: returnsSymbol)
                let returnsHasExperimentalContracts = returnsAnnotations.contains {
                    $0.annotationFQName == "ExperimentalContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
                }
                #expect(
                    returnsHasExperimentalContracts,
                    "Returns should carry ExperimentalContracts"
                )

                let builderFQName = contractsFQName + [interner.intern("ContractBuilder")]
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
                    fqName: builderFQName + [interner.intern("returns")]
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
                        && signature.parameterTypes == [sema.types.nullableAnyType]
                        && signature.returnType == returnsType
                }
                #expect(
                    hasValueParamReturns,
                    "ContractBuilder.returns(value) should return Returns"
                )

            }

            // === testReturnsNotNullInterfaceAndBuilderSurfaceAreRegistered ===

            do {

                let sample13Path = paths[13]

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let contractsFQName = [
                    interner.intern("kotlin"),
                    interner.intern("contracts"),
                ]
                let simpleEffectSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("SimpleEffect")])
                )
                let returnsNotNullSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("ReturnsNotNull")])
                )
                #expect(sema.symbols.symbol(returnsNotNullSymbol)?.kind == .interface)
                let returnsNotNullExtendsSimpleEffect = sema.symbols.directSupertypes(for: returnsNotNullSymbol).contains(simpleEffectSymbol)
                #expect(
                    returnsNotNullExtendsSimpleEffect,
                    "ReturnsNotNull must extend SimpleEffect"
                )
                let returnsNotNullAnnotations = sema.symbols.annotations(for: returnsNotNullSymbol)
                let returnsNotNullHasExperimentalContracts = returnsNotNullAnnotations.contains {
                    $0.annotationFQName == "ExperimentalContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
                }
                #expect(
                    returnsNotNullHasExperimentalContracts,
                    "ReturnsNotNull should carry ExperimentalContracts"
                )

                let builderFQName = contractsFQName + [interner.intern("ContractBuilder")]
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
                    fqName: builderFQName + [interner.intern("returnsNotNull")]
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

            // === testHoldsInInterfaceAndBuilderSurfaceAreRegistered ===

            do {

                let sample14Path = paths[14]

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                let contractsFQName = [
                    interner.intern("kotlin"),
                    interner.intern("contracts"),
                ]
                let effectSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("Effect")])
                )
                let holdsInSymbol = try #require(
                    sema.symbols.lookup(fqName: contractsFQName + [interner.intern("HoldsIn")])
                )
                #expect(sema.symbols.symbol(holdsInSymbol)?.kind == .interface)
                let holdsInExtendsEffect = sema.symbols.directSupertypes(for: holdsInSymbol).contains(effectSymbol)
                #expect(
                    holdsInExtendsEffect,
                    "HoldsIn must extend Effect"
                )
                let holdsInAnnotations = sema.symbols.annotations(for: holdsInSymbol)
                let holdsInHasExperimentalContracts = holdsInAnnotations.contains {
                    $0.annotationFQName == "ExperimentalContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalContracts"
                }
                #expect(
                    holdsInHasExperimentalContracts,
                    "HoldsIn should carry ExperimentalContracts"
                )
                let holdsInHasExperimentalExtended = holdsInAnnotations.contains {
                    $0.annotationFQName == "ExperimentalExtendedContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts"
                }
                #expect(
                    holdsInHasExperimentalExtended,
                    "HoldsIn should carry ExperimentalExtendedContracts"
                )

                let holdsInName = interner.intern("holdsIn")
                let holdsInFQName = contractsFQName + [holdsInName]
                let holdsInType = sema.types.make(.classType(ClassType(
                    classSymbol: holdsInSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let holdsInFunction = try #require(
                    (
                        sema.symbols.lookupAll(fqName: holdsInFQName)
                    ).first { symbol in
                        guard let signature = sema.symbols.functionSignature(for: symbol) else { return false }
                        return signature.receiverType == sema.types.booleanType
                            && signature.returnType == holdsInType
                    },
                    "Boolean.holdsIn should be source-backed"
                )
                let holdsInFnHasExperimentalExtended = sema.symbols.annotations(for: holdsInFunction).contains {
                    $0.annotationFQName == "ExperimentalExtendedContracts"
                        || $0.annotationFQName == "kotlin.contracts.ExperimentalExtendedContracts"
                }
                #expect(
                    holdsInFnHasExperimentalExtended,
                    "Boolean.holdsIn should carry ExperimentalExtendedContracts"
                )
                #expect(!(sema.symbols.symbol(holdsInFunction)?.flags.contains(.synthetic) ?? true))
                #expect(sema.symbols.symbol(holdsInFunction)?.declSite != nil)
                #expect(sema.symbols.externalLinkName(for: holdsInFunction) == nil)

            }

            // === testHoldsInBuilderSurfaceResolvesInSourceWithOptIn ===

            do {

                let sample15Path = paths[15]

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                #expect(
                    !sample15Diagnostics.contains { $0.severity == .error },
                    "Expected holdsIn contract surface to resolve: \(sample15Diagnostics.map(\.message))"
                )

            }

            // === testNonInlineContractPreservesNullableArgumentSmartCast ===

            do {

                let sample16Path = paths[16]

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                #expect(
                    !sample16Diagnostics.contains { $0.severity == .error },
                    "Expected non-inline contract smart cast to resolve: \(sample16Diagnostics.map(\.message))"
                )
                let assertNotNullSymbol = try #require(
                    sema.symbols.lookup(fqName: [
                        interner.intern("sample16"),
                        interner.intern("assertNotNull"),
                    ]),
                    "Non-inline assertNotNull should retain its source-backed contract effect"
                )
                #expect(sema.symbols.contractNonNullEffect(for: assertNotNullSymbol) != nil)
                let assertNotNullCalls = allExprIDsInPath(
                    in: ast,
                    path: sample16Path,
                    ctx: ctx
                ) { _, expr in
                    guard case let .call(calleeID, _, _, _) = expr,
                          let callee = ast.arena.expr(calleeID),
                          case let .nameRef(name, _) = callee
                    else {
                        return false
                    }
                    return interner.resolve(name) == "assertNotNull"
                }
                let chosenAssertNotNullCandidates = assertNotNullCalls.compactMap {
                    sema.bindings.callBinding(for: $0)?.chosenCallee
                }
                let chosenAssertNotNull = try #require(
                    chosenAssertNotNullCandidates.first,
                    "The sample16 assertNotNull call should have a chosen callee"
                )
                #expect(
                    chosenAssertNotNull == assertNotNullSymbol,
                    "The sample16 call should use its source-backed assertNotNull declaration"
                )

            }

            // === testNonNullContractDoesNotNarrowVariablesInsideBooleanArgument ===

            do {

                let sample17Path = paths[17]

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                #expect(
                    sample17Diagnostics.contains { $0.code == "KSWIFTK-SEMA-0026" },
                    "Expected nullable access to remain rejected after a Boolean argument: \(sample17Diagnostics.map(\.message))"
                )

            }

            // === testNonexistentBooleanImpliesReturnsNotNullIsRejected ===

            do {

                let sample18Path = paths[18]

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                #expect(
                    sample18Diagnostics.contains { $0.severity == .error },
                    "Expected nonexistent Boolean.implies(ReturnsNotNull) API to be rejected: \(sample18Diagnostics.map(\.message))"
                )

            }

        }
    }

}

#endif
