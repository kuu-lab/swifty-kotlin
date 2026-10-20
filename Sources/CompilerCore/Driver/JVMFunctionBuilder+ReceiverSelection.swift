extension JVMFunctionBuilder {
    func implicitExtensionReceiver(_ id: ExprID) -> JVMValue? {
        let bindings = program.sema.bindings
        return bindings.implicitExtensionReceiver(for: id).flatMap { contextualReceivers[$0] }
            ?? bindings.implicitReceiverOuterReceiver(for: id).flatMap { contextualReceivers[$0] }
            ?? extensionValue ?? thisValue
    }
}
