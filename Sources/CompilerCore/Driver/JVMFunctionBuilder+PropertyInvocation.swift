extension JVMFunctionBuilder {
    func nominalPropertyInvocation(_ id: ExprID, receiver: ExprID, args: [CallArgument]) throws -> JVMIntrinsicResult? {
        guard let binding = program.sema.bindings.invokeOperatorPropertyCalls[id],
              let property = program.properties[binding.property] else { return nil }
        if case .functionType = program.sema.types.kind(of: binding.propertyType) { return nil }

        // Getter evaluation precedes invoke arguments. Reuse the receiver AST
        // only as an operand key so the normal call paths keep defaults,
        // argument mapping, and virtual/interface/extension dispatch.
        let object = try requireValue(receiver)
        let raw = try readProperty(property, receiver: object, special: isSuper(receiver), superReceiver: receiver)
        let function = try convert(raw, to: program.type(binding.propertyType))
        let saved = evaluatedOperands
        evaluatedOperands[receiver] = function
        defer { evaluatedOperands = saved }
        if let result = try inlineCall(args, receiver: receiver, id: id) { return result }
        if let result = try textLibraryCall(args, receiver: receiver, id: id) { return result }
        if let result = try sourceCall(args, receiver: receiver, id: id) { return result }
        if let result = try extensionOrInvoke(receiver, name: context.interner.intern("invoke"), args: args, id: id) { return result }
        if let call = program.sema.bindings.callBinding(for: id),
           let method = program.methods[call.chosenCallee] ?? context.jvmImports?.methods[call.chosenCallee] {
            return JVMIntrinsicResult(value: try foreign(method, receiver: method.isStatic ? nil : function, args: args, id: id))
        }
        throw fail("Missing JVM property invoke target.", id)
    }
}
