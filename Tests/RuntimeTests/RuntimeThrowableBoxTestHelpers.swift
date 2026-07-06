@testable import Runtime

func runtimeThrowableBoxHasExactType(
    _ box: RuntimeThrowableBox,
    _ expectedType: RuntimeThrowableBox.Type
) -> Bool {
    ObjectIdentifier(Swift.type(of: box)) == ObjectIdentifier(expectedType)
}

func runtimeValueIsThrowableBox(_ value: Any) -> Bool {
    value is RuntimeThrowableBox
}
