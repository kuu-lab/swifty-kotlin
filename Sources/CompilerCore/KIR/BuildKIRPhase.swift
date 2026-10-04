
public final class BuildKIRPhase: CompilerPhase {
    public static let name = "BuildKIR"

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard let ast = ctx.ast, let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Sema phase did not run.")
        }

        // Lowering recurses with large frames; run it on a big-stack thread so
        // it cannot overflow the 512 KiB cooperative-pool stacks under
        // `swift test --parallel` (flaky SIGBUS / signal 10).
        let work = LoweringWork(ctx: ctx, ast: ast, sema: sema)
        let module = try LargeStackExecutor.run {
            try work.run()
        }

        if module.functionCount == 0, !ctx.diagnostics.hasError {
            ctx.diagnostics.warning(
                "KSWIFTK-KIR-0001",
                "No function declarations found.",
                range: nil
            )
        }
        ctx.storeKIR(module)
    }
}

/// Holds the non-`Sendable` lowering inputs and exposes a `@Sendable` callable
/// surface so the large-stack thread can run `lowerModule` without capturing
/// non-`Sendable` values through `withoutActuallyEscaping` closures.
private final class LoweringWork: @unchecked Sendable {
    let ctx: CompilationContext
    let ast: ASTModule
    let sema: SemaModule

    init(ctx: CompilationContext, ast: ASTModule, sema: SemaModule) {
        self.ctx = ctx
        self.ast = ast
        self.sema = sema
    }

    func run() throws -> KIRModule {
        let loweringCtx = KIRLoweringContext()
        let driver = KIRLoweringDriver(ctx: loweringCtx)
        return driver.lowerModule(ast: ast, sema: sema, compilationCtx: ctx)
    }
}
