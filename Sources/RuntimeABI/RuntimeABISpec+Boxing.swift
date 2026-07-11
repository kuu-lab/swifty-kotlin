// swiftlint:disable file_length

/// `RuntimeABISpec.boxingFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let boxingFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_box_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_is_initialized",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_get_or_throw",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "propertyName", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_int",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_bool",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_long",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_float",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_double",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_char",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_tag_value_class_box",
            parameters: [
                RuntimeABIParameter(name: "boxedRaw", type: .intptr),
                RuntimeABIParameter(name: "classID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing",
            isThrowing: false
        ),
    ]
}
