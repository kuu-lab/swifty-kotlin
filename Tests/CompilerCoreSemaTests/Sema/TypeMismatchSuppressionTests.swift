#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-3953: kotlinc K2's position-specific type-mismatch diagnostic names
// (verified against kotlinc 2.4.20) must suppress the dedicated KSwiftK
// diagnostic emitted at the matching position. Each name maps to a dedicated
// internal code, never to the generic KSWIFTK-TYPE-0001 / KSWIFTK-SEMA-0002
// codes, so an upstream name cannot silence unrelated failures.
@Suite
struct TypeMismatchSuppressionTests {
    private func context(for source: String) throws -> CompilationContext {
        try semaContext(for: [source])
    }

    // MARK: - INCOMPATIBLE_TYPES -> KSWIFTK-SEMA-0466

    @Test func whenBranchMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun f(x: Int): Int = when (x) {
                "s" -> 1
                else -> 2
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0466", in: ctx)
    }

    @Test func incompatibleTypesSuppressesWhenBranchMismatch() throws {
        let ctx = try context(for: """
            @Suppress("INCOMPATIBLE_TYPES")
            fun f(x: Int): Int = when (x) {
                "s" -> 1
                else -> 2
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0466", in: ctx)
    }

    @Test func conditionTypeMismatchDoesNotSuppressWhenBranchMismatch() throws {
        // kotlinc keeps INCOMPATIBLE_TYPES and CONDITION_TYPE_MISMATCH as
        // separate diagnostics: the wrong name must not hide the error.
        let ctx = try context(for: """
            @Suppress("CONDITION_TYPE_MISMATCH")
            fun f(x: Int): Int = when (x) {
                "s" -> 1
                else -> 2
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0466", in: ctx)
    }

    // MARK: - INITIALIZER_TYPE_MISMATCH -> KSWIFTK-SEMA-0468

    @Test func initializerMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            val x: Int = "s"
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
    }

    @Test func initializerTypeMismatchSuppressesInitializerError() throws {
        let ctx = try context(for: """
            @Suppress("INITIALIZER_TYPE_MISMATCH")
            val x: Int = "s"
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
    }

    @Test func initializerTypeMismatchSuppressesObjectLiteralProperty() throws {
        // An anonymous object's property initializer is an initializer
        // position upstream.
        let ctx = try context(for: """
            @Suppress("INITIALIZER_TYPE_MISMATCH")
            fun obj() = object { val p: Int = "x" }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    // MARK: - ARGUMENT_TYPE_MISMATCH -> KSWIFTK-SEMA-0473

    @Test func argumentMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun g(i: Int) = i
            fun h() = g("s")
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesArgumentError() throws {
        let ctx = try context(for: """
            fun g(i: Int) = i
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun h() = g("s")
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesMultiCandidateMismatch() throws {
        // kotlinc reports ARGUMENT_TYPE_MISMATCH even when several overloads
        // were evaluated, as long as the failure is an argument type
        // mismatch (verified against kotlinc 2.4.20).
        let ctx = try context(for: """
            fun m(i: Int) = i
            fun m(s: String, b: Boolean) = s
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun call() = m(1.5)
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func argumentTypeMismatchDoesNotSuppressNoneApplicable() throws {
        // When every candidate fails before the arguments type-check (arity,
        // unknown named parameters) kotlinc reports NONE_APPLICABLE, not
        // ARGUMENT_TYPE_MISMATCH — the alias must not silence the generic
        // overload-resolution failure.
        let ctx = try context(for: """
            fun m(i: Int) = i
            fun m(s: String, b: Boolean) = s
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun call() = m(1, "x", true)
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
    }

    @Test func argumentTypeMismatchDoesNotSuppressOperatorNoneApplicable() throws {
        // Operator-syntax calls keep the generic overload diagnostic when
        // several operator candidates are inapplicable — kotlinc reports
        // NONE_APPLICABLE there, not ARGUMENT_TYPE_MISMATCH.
        let ctx = try context(for: """
            class Foo
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun probe() = 1 + Foo()
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesVarargMismatch() throws {
        // A lone non-array argument to a vararg parameter is an argument
        // type mismatch in kotlinc.
        let ctx = try context(for: """
            fun v(vararg xs: Int) = xs.size
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun call() = v("s")
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesCallableValueInvoke() throws {
        // Calling a function value with a mismatched argument is an argument
        // type mismatch in kotlinc (f("bad") for f: (Int) -> Int).
        let ctx = try context(for: """
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun call(f: (Int) -> Int) = f("s")
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesArrayConstructorSize() throws {
        // The size argument of an array constructor is an ordinary argument
        // position upstream.
        let ctx = try context(for: """
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun a() = IntArray("s")
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func argumentTypeMismatchSuppressesIndexedAccess() throws {
        // `a[i]` desugars to `get(i)`/`set(i, v)` — the index is an argument.
        let ctx = try context(for: """
            @Suppress("ARGUMENT_TYPE_MISMATCH")
            fun idx(a: IntArray) = a["s"]
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0473", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    // MARK: - RETURN_TYPE_MISMATCH -> KSWIFTK-SEMA-0469

    @Test func returnMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun r(): Int = "s"
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0469", in: ctx)
    }

    @Test func returnTypeMismatchSuppressesReturnError() throws {
        let ctx = try context(for: """
            @Suppress("RETURN_TYPE_MISMATCH")
            fun r(): Int = "s"
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0469", in: ctx)
    }

    @Test func returnTypeMismatchSuppressesLambdaBodyMismatch() throws {
        // A lambda body's last expression is its return: kotlinc reports
        // RETURN_TYPE_MISMATCH for `()->Int = { "x" }`.
        let ctx = try context(for: """
            fun pass(f: () -> Int) {}
            @Suppress("RETURN_TYPE_MISMATCH")
            fun use() = pass({ "x" })
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0469", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    // MARK: - CONDITION_TYPE_MISMATCH -> KSWIFTK-SEMA-0467 / KSWIFTK-SEMA-0032

    @Test func ifConditionMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun c() {
                if ("s") {}
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0467", in: ctx)
    }

    @Test func conditionTypeMismatchSuppressesIfCondition() throws {
        let ctx = try context(for: """
            @Suppress("CONDITION_TYPE_MISMATCH")
            fun c() {
                if ("s") {}
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0467", in: ctx)
    }

    @Test func conditionTypeMismatchSuppressesWhileCondition() throws {
        let ctx = try context(for: """
            @Suppress("CONDITION_TYPE_MISMATCH")
            fun c() {
                while ("s") {}
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0467", in: ctx)
    }

    @Test func conditionTypeMismatchSuppressesSubjectlessWhenBranch() throws {
        // Subjectless-when branch conditions predate this change and keep
        // their dedicated code; the upstream name covers both codes.
        let ctx = try context(for: """
            @Suppress("CONDITION_TYPE_MISMATCH")
            fun w(x: Int) = when {
                "s" -> 1
                else -> 2
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    // MARK: - ASSIGNMENT_TYPE_MISMATCH -> KSWIFTK-SEMA-0470

    @Test func assignmentMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun a() {
                var x: Int = 0
                x = "s"
            }
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0470", in: ctx)
    }

    @Test func assignmentTypeMismatchSuppressesAssignmentError() throws {
        let ctx = try context(for: """
            @Suppress("ASSIGNMENT_TYPE_MISMATCH")
            fun a() {
                var x: Int = 0
                x = "s"
            }
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0470", in: ctx)
    }

    // MARK: - EQUALITY_NOT_APPLICABLE -> KSWIFTK-SEMA-0471

    @Test func equalityMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun e(x: Int) = x == "s"
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0471", in: ctx)
    }

    @Test func equalityNotApplicableSuppressesEqualityError() throws {
        let ctx = try context(for: """
            @Suppress("EQUALITY_NOT_APPLICABLE")
            fun e(x: Int) = x == "s"
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0471", in: ctx)
    }

    // MARK: - FORBIDDEN_IDENTITY_EQUALS -> KSWIFTK-SEMA-0472

    @Test func identityMismatchEmitsDedicatedCode() throws {
        let ctx = try context(for: """
            fun i(x: Int) = x === "s"
            """)
        assertHasDiagnostic("KSWIFTK-SEMA-0472", in: ctx)
    }

    @Test func forbiddenIdentityEqualsSuppressesIdentityError() throws {
        let ctx = try context(for: """
            @Suppress("FORBIDDEN_IDENTITY_EQUALS")
            fun i(x: Int) = x === "s"
            """)
        assertNoDiagnostic("KSWIFTK-SEMA-0472", in: ctx)
    }
}
#endif
