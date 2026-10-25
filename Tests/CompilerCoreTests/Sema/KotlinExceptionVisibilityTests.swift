@testable import CompilerCore
import Testing

@Suite
struct KotlinExceptionVisibilityTests {
    @Test
    func kotlinNullPointerExceptionIsPublicButKotlinNothingValueExceptionIsInternal() throws {
        try checkVisibility(emit: .executable)
    }

    @Test
    func jvmOverlayKotlinNullPointerExceptionIsPublicButKotlinNothingValueExceptionIsInternal() throws {
        try withTemporaryFile(contents: jvmProbeSource) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .jvmJar, includeStdlib: false)
            for sourcePath in [
                "kotlin/KotlinNullPointerException.kt",
                "kotlin/KotlinNothingValueException.kt",
            ] {
                let source = try JVMStdlibCatalog.read(sourcePath)
                _ = ctx.sourceManager.addFile(
                    path: "<test-jvm-stdlib>/\(sourcePath)",
                    contents: source,
                    origin: .bundledStdlib
                )
            }
            try JVMPreparationPhase().run(ctx)
            try runSema(ctx)
            try expectExceptionVisibility(in: ctx)
        }
    }

    private func checkVisibility(emit: EmitMode) throws {
        try withTemporaryFile(contents: probeSource) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: emit)
            try runSema(ctx)
            try expectExceptionVisibility(in: ctx)
        }
    }

    private var probeSource: String {
        """
        fun probe() {
            KotlinNullPointerException()
            KotlinNullPointerException("message")
            KotlinNothingValueException()
            UninitializedPropertyAccessException()
            TypeCastException()
            NotImplementedError()
        }
        """
    }

    private var jvmProbeSource: String {
        """
        fun probe() {
            KotlinNullPointerException()
            KotlinNullPointerException("message")
            KotlinNothingValueException()
        }
        """
    }

    private func expectExceptionVisibility(in ctx: CompilationContext) throws {
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        let error = try #require(errors.first)
        #expect(error.code == "KSWIFTK-SEMA-0044", "\(error)")
        #expect(error.message.contains("KotlinNothingValueException"), "\(error)")
    }
}
