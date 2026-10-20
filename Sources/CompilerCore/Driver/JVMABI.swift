private let continuationType = JVMValueType.reference("kotlin/coroutines/Continuation", nullable: false)
private let coroutineObject = JVMValueType.reference("java/lang/Object", nullable: true)

extension JVMFunctionReference {
    public var suspendABI: JVMFunctionReference {
        JVMFunctionReference(name: name, parameters: Array(parameters.dropLast(suspendDefaultMasks == 0 ? 0 : suspendDefaultMasks + 1)) + [continuationType] + (suspendDefaultMasks == 0 ? [] : Array(parameters.suffix(suspendDefaultMasks + 1))), result: coroutineObject, owner: owner, ownerIsInterface: ownerIsInterface)
    }
}

extension JVMForeignMethod {
    public var suspendABI: JVMForeignMethod {
        // FunctionN erases every argument, including its continuation, to Object.
        let continuation = owner.hasPrefix("kotlin/jvm/functions/Function") && name == "invoke" ? coroutineObject : continuationType
        var method = JVMForeignMethod(owner: owner, name: name, descriptor: "(" + (parameters + [continuation]).map(\.descriptor).joined() + ")Ljava/lang/Object;", parameters: parameters + [continuation], result: coroutineObject, isStatic: isStatic, isInterface: isInterface, isAbstract: isAbstract)
        method.isSpecial = isSpecial
        return method
    }
}
