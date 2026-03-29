// KFunction / KProperty / KConstructor dynamic call ABI specs (STDLIB-REFLECT-067)

public extension RuntimeABISpec {
    /// KFunction, KProperty, and KConstructor dynamic call runtime functions.
    static let kFunctionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_create",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "nameHandle", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeHandle", type: .intptr),
                RuntimeABIParameter(name: "isSuspend", type: .intptr),
                RuntimeABIParameter(name: "parametersHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_arity",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_is_suspend",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_0",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_1",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_2",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_3",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "argsList", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_get",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_set",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_0",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_1",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "argsList", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflect"
        ),
    ]
}
