import CompilerCore

public func makeBackendPhases() -> [CompilerPhase] {
    [CodegenPhase(), LinkPhase()]
}
