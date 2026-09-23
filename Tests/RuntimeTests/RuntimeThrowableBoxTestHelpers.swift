@testable import Runtime

func runtimeThrowableBoxHasExactType(
    _ box: RuntimeThrowableBox,
    _ expectedType: RuntimeThrowableBox.Type
) -> Bool {
    ObjectIdentifier(Swift.type(of: box)) == ObjectIdentifier(expectedType)
}

func runtimeThrowableBox(from raw: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

func runtimeValueIsThrowableBox(_ value: Any) -> Bool {
    value is RuntimeThrowableBox
}
