@testable import Runtime
import Testing

/// Regression coverage for a bug where `kk_op_is`'s nominal-type branch always
/// returned a match for any RuntimeThrowableBox-based exception, regardless of
/// the requested catch type. This meant `catch (e: IllegalStateException)`
/// incorrectly caught a `ClassCastException` (or any other exception whose
/// hierarchy lookup missed), because the "unknown nominal token" fallback
/// unconditionally returned 1 even when the throwable's real hierarchy was
/// known and simply didn't contain the requested type.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeExceptionTypeDiscriminationTests {
    // Mirrors RuntimeTypeCheckToken's encoding (CompilerCore/KIR/RuntimeTypeCheckToken.swift);
    // kept in sync per that type's own doc comment.
    private static let nominalBase: Int64 = 6
    private static let stringBaseToken = 2
    private static let payloadShift: Int64 = 9

    private func nominalTypeToken(for fqName: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: fqName)
        return Int(Self.nominalBase | (typeID << Self.payloadShift))
    }

    private func throwableBox(from raw: Int) -> RuntimeThrowableBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return tryCast(ptr, to: RuntimeThrowableBox.self)
    }

    // MARK: - kk_op_cast: `(42 as Any) as String` style failure (the reported repro)

    @Test func failedAsCastThrowsTypedClassCastException() throws {
        var thrown = 0
        let result = kk_op_cast(42, Self.stringBaseToken, &thrown)

        #expect(result == 0)
        #expect(thrown != 0)
        let box = try #require(throwableBox(from: thrown))
        #expect(runtimeThrowableBoxHasExactType(box, RuntimeClassCastExceptionBox.self))
    }

    @Test func classCastExceptionMatchesItsOwnHierarchy() {
        var thrown = 0
        _ = kk_op_cast(42, Self.stringBaseToken, &thrown)

        for fqName in [
            "kotlin.ClassCastException",
            "kotlin.RuntimeException",
            "kotlin.Exception",
            "kotlin.Throwable",
        ] {
            #expect(
                kk_op_is(thrown, nominalTypeToken(for: fqName)) == 1,
                "ClassCastException should satisfy an is/catch check for \(fqName)"
            )
        }
    }

    /// The exact bug from the report: `catch (e: IllegalStateException)` must NOT
    /// catch a ClassCastException — they are unrelated sibling RuntimeException
    /// subtypes, not a super/subtype pair.
    @Test func classCastExceptionDoesNotMatchUnrelatedSiblingTypes() {
        var thrown = 0
        _ = kk_op_cast(42, Self.stringBaseToken, &thrown)

        for fqName in [
            "kotlin.IllegalStateException",
            "kotlin.IllegalArgumentException",
            "kotlin.ArithmeticException",
            "kotlin.NoSuchElementException",
        ] {
            #expect(
                kk_op_is(thrown, nominalTypeToken(for: fqName)) == 0,
                "ClassCastException must not satisfy an is/catch check for unrelated \(fqName)"
            )
        }
    }

    // MARK: - General nominalBase discrimination (not ClassCastException-specific)

    /// Confirms the underlying `kk_op_is` fix generalizes to every typed
    /// RuntimeThrowableBox subclass (STDLIB-LOG-149 and friends), not just the
    /// newly-typed ClassCastException.
    @Test func illegalStateExceptionDoesNotMatchUnrelatedSiblingTypes() {
        let thrown = runtimeAllocateIllegalStateException(message: "bad state")

        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.IllegalStateException")) == 1)
        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.Exception")) == 1)
        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.ClassCastException")) == 0)
        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.ArithmeticException")) == 0)
    }

    /// Untyped/generic throwables (allocated via the base `runtimeAllocateThrowable`,
    /// used throughout the runtime for internal errors with no dedicated Kotlin
    /// exception type) intentionally keep the broad "matches any catch clause"
    /// fallback, since the runtime genuinely cannot tell their Kotlin type. This
    /// pins down that the fix does not overcorrect into making these uncatchable.
    @Test func untypedThrowableStillMatchesAnyNominalCatchClauseByDesign() {
        let thrown = runtimeAllocateThrowable(message: "Some internal runtime error")

        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.IllegalStateException")) == 1)
        #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.ArithmeticException")) == 1)
    }
}
