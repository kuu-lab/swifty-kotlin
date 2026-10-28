import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct InternalAnnotationConstructionTests {
    @Test(arguments: ["source", "fresh .kklib"])
    func fullyQualifiedInternalAnnotationsRespectSuppressionAndConstructorVisibility(surface: String) throws {
        let source = """
        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @kotlin.internal.InlineOnly
        fun suppressedFunction(value: Int): Int = value

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @kotlin.internal.InlineOnly
        val suppressedProperty: Int = 1

        class SuppressedPrimary @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            @kotlin.internal.KsNoInline constructor()

        class RejectedPrimary @kotlin.internal.KsNoInline constructor()

        class Secondary() {
            @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            @kotlin.internal.KsNoInline constructor(value: Int) : this()

            @kotlin.internal.KsNoInline constructor(value: String) : this()
        }

        fun localConstructors() {
            class SuppressedLocalPrimary @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
                @kotlin.internal.KsNoInline constructor()

            class RejectedLocalPrimary @kotlin.internal.KsNoInline constructor()

            class LocalSecondary() {
                @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
                @kotlin.internal.KsNoInline constructor(value: Int) : this()

                @kotlin.internal.KsNoInline constructor(value: String) : this()
            }
        }

        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.BINARY)
        annotation class BinaryTag(val value: String)

        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeTag(val value: String)

        @BinaryTag() fun missingBinaryArgument() {}
        @BinaryTag(1) fun wrongBinaryArgumentType() {}
        @RuntimeTag() fun missingRuntimeArgument() {}
        @RuntimeTag(1) fun wrongRuntimeArgumentType() {}
        @BinaryTag("wrong target") class BinaryTargetError
        @RuntimeTag("wrong target") class RuntimeTargetError

        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.BINARY)
        @Deprecated("Use another annotation", level = DeprecationLevel.ERROR)
        annotation class DeprecatedBinaryTag

        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.RUNTIME)
        @Deprecated("Use another annotation", level = DeprecationLevel.ERROR)
        annotation class DeprecatedRuntimeTag

        @DeprecatedBinaryTag fun binaryDeprecationError() {}
        @DeprecatedRuntimeTag fun runtimeDeprecationError() {}
        @Suppress("DEPRECATION_ERROR") @DeprecatedBinaryTag fun suppressedBinaryDeprecationError() {}
        @Suppress("DEPRECATION_ERROR") @DeprecatedRuntimeTag fun suppressedRuntimeDeprecationError() {}

        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        @Retention(AnnotationRetention.BINARY)
        annotation class BinaryMarker

        @BinaryMarker
        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.BINARY)
        annotation class ExperimentalBinaryTag

        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeMarker

        @RuntimeMarker
        @Target(AnnotationTarget.FUNCTION)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class ExperimentalRuntimeTag

        @ExperimentalBinaryTag fun binaryOptInError() {}
        @ExperimentalRuntimeTag fun runtimeOptInError() {}
        @Suppress("OPT_IN_USAGE") @ExperimentalBinaryTag fun suppressedBinaryOptInError() {}
        @Suppress("OPT_IN_USAGE") @ExperimentalRuntimeTag fun suppressedRuntimeOptInError() {}
        """

        let libraryPath: String?
        if surface == "fresh .kklib" {
            TestStdlibCache.shared.prepare()
            libraryPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            libraryPath = nil
        }

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(
                inputs: [path],
                includeStdlib: libraryPath == nil,
                stdlibLibraryPath: libraryPath,
                allowDefaultStdlibLibrary: false
            )
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0044" }.count == 4, "Unexpected visibility errors for \(surface): \(errors)")
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }.count == 2, "Unexpected target errors for \(surface): \(errors)")
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0002" }.count == 4, "Unexpected argument errors for \(surface): \(errors)")
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }.count == 2, "Unexpected deprecation errors for \(surface): \(errors)")
            #expect(errors.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }.count == 2, "Unexpected opt-in errors for \(surface): \(errors)")
            #expect(!errors.contains { $0.message.contains("Unresolved reference 'kotlin'") })
        }
    }
}
