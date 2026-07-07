// swiftlint:disable file_length

/// `RuntimeABISpec.testFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let testFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals_message",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue_message",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull_message",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
    ]
}
