@testable import CompilerCore
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

func makeExpressionAnnotationContext(inputs: [String]) throws -> CompilationContext {
    TestStdlibCache.shared.prepare()
    let library = try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib must be prepared")
    return makeCompilationContext(inputs: inputs, stdlibLibraryPath: library)
}

@Suite
struct ExpressionAnnotationSemanticTests {
    @Test(arguments: [
        #""DEPRECATION""#,
        #""\u0044EPRECATION""#,
        #""""DEPRECATION""""#,
        #"$$"DEPRECATION""#,
        #"$$"""DEPRECATION""""#,
    ])
    func canonicalSuppressStringsAreDecodedWithinTheOperand(literal: String) throws {
        let source = """
        @Deprecated("old") fun old(): Int = 7
        fun quiet(): Int = @Suppress(\(literal)) old()
        fun noisy(): Int = old()
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let warnings = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(warnings.count == 1, "\(warnings)")
        }
    }

    @Test
    func concatenatedSuppressNameKeepsTheReferenceWarningAndOtherArgumentsStillApply() throws {
        let source = """
        @Deprecated("old") fun old(): Int = 7
        fun noisyConcat(): Int = @Suppress("DEPRE" + "CATION") old()
        fun mixed(): Int = @Suppress("DEPRE" + "CATION", "DEPRECATION") old()
        fun noisy(): Int = old()
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            #expect(context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }.count == 2)
        }
    }

    @Test
    func rawSuppressStringsDoNotDecodeEscapes() throws {
        let source = #"""
        @Deprecated("old") fun old(): Int = 7
        fun noisy(): Int = @Suppress("""\u0044EPRECATION""") old()
        """#
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            #expect(context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }.count == 1)
        }
    }

    @Test
    func suppressAppliesOnlyToAnnotatedOperandAndKeepsSeverityPolicy() throws {
        let source = """
        @Deprecated("old") fun old(): Int = 7
        @Deprecated("error", level = DeprecationLevel.ERROR) fun forbidden(): Int = 8
        fun quiet(): Int = @Suppress("DEPRECATION") old()
        fun noisy(): Int = old()
        fun stillError(): Int = @Suppress("DEPRECATION") forbidden()
        fun quietError(): Int = @Suppress("DEPRECATION_ERROR") forbidden()
        fun binary(): Int = @Suppress("DEPRECATION") old() + old()
        fun block(flag: Boolean): Int = when {
            flag -> @Suppress("DEPRECATION") { old() }
            else -> old()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            let deprecations = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(deprecations.filter { $0.severity == .warning }.count == 3, "\(deprecations)")
            #expect(deprecations.filter { $0.severity == .error }.count == 1, "\(deprecations)")
            #expect(context.diagnostics.diagnostics.filter { $0.severity == .error }.count == 1)
        }
    }

    @Test
    func expressionTargetIsCheckedIncludingLexicalAnnotationOwners() throws {
        let source = """
        @Target(AnnotationTarget.EXPRESSION) @Retention(AnnotationRetention.SOURCE)
        annotation class ExpressionTag
        @Target(AnnotationTarget.FUNCTION) annotation class FunctionTag
        fun valid(): Int = @ExpressionTag 7
        fun validLambda(): () -> Int = @FunctionTag { 7 }
        fun validAnonymous(): () -> Int = @FunctionTag fun(): Int { return 7 }
        fun expressionLambda(): () -> Int = @ExpressionTag { 8 }
        fun expressionAnonymous(): () -> Int = @ExpressionTag fun(): Int { return 8 }
        fun invalid(): Int = @FunctionTag 8
        class Owner {
            @Target(AnnotationTarget.FUNCTION) annotation class ExpressionTag
            fun nestedInvalid(): Int = @ExpressionTag 9
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 2, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
        }
    }

    @Test
    func expressionUseSiteTargetIsRejected() throws {
        try withTemporaryFile(contents: "fun invalid(): Int = @get:Suppress(\"UNUSED\") 7") { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-PARSE-ANNOTATION-TARGET"
            })
        }
    }

    @Test
    func annotationDoesNotHideOperandTypeErrorsOrPrivateAccess() throws {
        let source = """
        class Owner { private fun hidden(): Int = 7 }
        fun badType(): Int = @Suppress("UNUSED") "text"
        fun badAccess(): Int = @Suppress("DEPRECATION") Owner().hidden()
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count >= 2, "\(errors)")
            #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0469" })
            #expect(errors.contains { $0.message.lowercased().contains("private") || $0.message.lowercased().contains("visible") })
        }
    }

    @Test
    func aliasesAndShadowedSuppressKeepTheirResolvedMeaning() throws {
        let source = """
        import kotlin.Suppress as Quiet
        @Deprecated("old") fun old(): Int = 7
        fun quiet(): Int = @Quiet("DEPRECATION") old()
        class Owner {
            @Target(AnnotationTarget.EXPRESSION) @Retention(AnnotationRetention.SOURCE)
            annotation class Suppress(val value: String)
            fun noisy(): Int = @Suppress("DEPRECATION") old()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let warnings = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(warnings.count == 1, "\(warnings)")
        }
    }

    @Test
    func expressionAnnotationCannotAccessPrivateClassifierFromAnotherFile() throws {
        let producer = """
        @Target(AnnotationTarget.EXPRESSION) @Retention(AnnotationRetention.SOURCE)
        private annotation class Hidden
        fun valid(): Int = @Hidden 7
        """
        let consumer = """
        fun invalid(): Int = @Hidden 8
        fun invalidIncrement(): Int { var value = 1; return ++@Hidden value }
        fun invalidIndexedIncrement(): Int { val values = IntArray(1); return ++@Hidden values[0] }
        """
        try withTemporaryFile(contents: producer) { producerPath in
            try withTemporaryFile(contents: consumer) { consumerPath in
                let context = try makeExpressionAnnotationContext(inputs: [producerPath, consumerPath])
                try runSema(context)
                let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.count == 3, "\(errors)")
                #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0040" }, "\(errors)")
                #expect(errors.allSatisfy { $0.primaryRange?.start.file == context.sourceManager.fileID(forPath: consumerPath) })
            }
        }
    }

    @Test
    func declarationPositionSuppressCoversLocalValAndVarInitializers() throws {
        // KUU-3920: a statement-initial @Suppress on a local val/var applies to
        // the whole declaration, including its initializer — matching kotlinc
        // and the existing local-fun behavior.
        let source = """
        @Deprecated("old") fun old(): Int = 7
        fun quietVal(): Int {
            @Suppress("DEPRECATION")
            val result = old()
            return result
        }
        fun quietVar(): Int {
            @Suppress("DEPRECATION")
            var result = old()
            result += 1
            return result
        }
        fun noisy(): Int {
            val result = old()
            return result
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let warnings = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(warnings.count == 1, "\(warnings)")
        }
    }

    @Test
    func optInOnLocalFunctionCoversSignatureAndBody() throws {
        // KUU-4290: annotations on a local `fun` reach Sema, so `@OptIn`
        // consents to experimental API in its signature and body — matching
        // kotlinc, which compiles the contracts repro cleanly.
        let source = """
        @RequiresOptIn
        annotation class ExperimentalFeature

        @ExperimentalFeature
        class ExperimentalType

        @ExperimentalFeature
        fun experimentalApi(): Int = 1

        fun optedIn(): Int {
            @OptIn(ExperimentalFeature::class)
            fun helper(x: ExperimentalType): Int {
                return experimentalApi()
            }
            return 0
        }

        fun notOptedIn(): Int {
            fun helper(): Int {
                return experimentalApi()
            }
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            let optInErrors = context.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-OPT-IN"
            }
            // Only the un-annotated local function's body reports; the
            // @OptIn-annotated one's signature and body stay clean.
            #expect(optInErrors.count == 1, "\(optInErrors)")
        }
    }

    @Test
    func deprecatedOnLocalFunctionWarnsAtCallSite() throws {
        // KUU-4290: symbol annotation registration makes `@Deprecated` on a
        // local function observable at its call sites.
        let source = """
        fun outer(): Int {
            @Deprecated("old")
            fun helper(): Int = 1
            return helper()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let warnings = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }
            #expect(warnings.count == 1, "\(warnings)")
        }
    }

    @Test
    func localFunctionAnnotationsValidateAgainstFunctionTarget() throws {
        // KUU-4290: local `fun` annotations are declaration-site — they must
        // satisfy FUNCTION targets, not EXPRESSION targets.
        let source = """
        annotation class AnyTag
        @Target(AnnotationTarget.EXPRESSION) annotation class ExpressionTag

        fun outer(): Int {
            @AnyTag
            fun ok(): Int = 1
            @ExpressionTag
            fun bad(): Int = 2
            return ok() + bad()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }, "\(errors)")
        }
    }

    @Test
    func unresolvedAnnotationOnLocalFunctionIsReported() throws {
        // KUU-4290: annotations are no longer silently dropped, so an
        // unresolvable one on a local function reports like any declaration.
        let source = """
        fun outer(): Int {
            @NoSuchAnnotation
            fun helper(): Int = 1
            return helper()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = try makeExpressionAnnotationContext(inputs: [path])
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0022"
            }, "\(context.diagnostics.diagnostics)")
        }
    }
}
