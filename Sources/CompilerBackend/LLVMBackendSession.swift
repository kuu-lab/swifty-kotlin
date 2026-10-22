/// Retains LLVM process state for one Codegen/Link pipeline.
final class LLVMBackendSession {
    private var bindings: LLVMCAPIBindings?
    private let keepContextAlive: Bool
    private var context: LLVMCAPIBindings.LLVMContextRef?

    init(keepContextAlive: Bool = false) {
        self.keepContextAlive = keepContextAlive
    }

    func loadBindings() -> LLVMCAPIBindings? {
        if let bindings { return bindings }
        // Cache successful loads only; preserve trust checks and the context
        // lifecycle smoke test on the first load of each compilation.
        let loaded = LLVMCAPIBindings.loadUsable()
        bindings = loaded
        return loaded
    }

    func reusableContext(for bindings: LLVMCAPIBindings) -> LLVMCAPIBindings.LLVMContextRef? {
        guard keepContextAlive else { return nil }
        if let context { return context }
        let created = bindings.createContext()
        context = created
        return created
    }

    deinit {
        if let context {
            bindings?.disposeContext(context)
        }
    }
}
