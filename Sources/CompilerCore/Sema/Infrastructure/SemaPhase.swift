
import Dispatch

/// Records Sema intervals on the caller thread only. Worker threads must not
/// mutate PhaseTimer; a future parallel pass must time its dispatch and join here.
func withSemaSubPhaseTiming<T>(
    _ name: String,
    ctx: CompilationContext,
    _ body: () throws -> T
) rethrows -> T {
    guard let timer = ctx.phaseTimer else { return try body() }
    let start = DispatchTime.now().uptimeNanoseconds
    defer {
        timer.recordSubPhase(name, startTime: start, endTime: DispatchTime.now().uptimeNanoseconds)
    }
    return try body()
}

public final class SemaPhase: CompilerPhase {
    public static let name = "Sema"

    private let passes: [CompilerPhase] = [
        DataFlowSemaPhase(),
        TypeCheckSemaPhase(),
    ]

    public init() {}

    public func run(_ ctx: CompilationContext) throws {
        guard ctx.ast != nil else {
            throw CompilerPipelineError.invalidInput("AST phase did not run.")
        }
        for phase in passes {
            try phase.run(ctx)
        }
    }
}
