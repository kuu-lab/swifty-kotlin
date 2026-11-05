
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
        // Header/import passes decode bundled-stdlib metadata with recursion
        // depth that grows with the artifact; on the 512 KiB cooperative-pool
        // stacks used by `swift test` that overflows (SIGBUS). Run both passes
        // on a big-stack thread so headroom is independent of the caller,
        // matching BuildKIRPhase/TypeCheckSemaPhase. The hop is serial — the
        // caller blocks until the passes join — so PhaseTimer mutations inside
        // stay ordered with the surrounding beginPhase/endPhase pair.
        let work = SemaPhaseWork(passes: passes, ctx: ctx)
        try LargeStackExecutor.run { try work.run() }
    }
}

/// Holds the non-`Sendable` pass list so the large-stack thread can run them
/// without capturing non-`Sendable` values through escaping closures.
private final class SemaPhaseWork: @unchecked Sendable {
    let passes: [CompilerPhase]
    let ctx: CompilationContext

    init(passes: [CompilerPhase], ctx: CompilationContext) {
        self.passes = passes
        self.ctx = ctx
    }

    func run() throws {
        for phase in passes {
            try withSubPhaseTiming(type(of: phase).name, timer: ctx.phaseTimer) {
                try phase.run(ctx)
            }
        }
    }
}
