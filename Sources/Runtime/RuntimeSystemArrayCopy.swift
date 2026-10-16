import RuntimeABI

@_cdecl("__kk_system_arraycopy")
public func kk_system_arraycopy(
    _ sourceRaw: Int,
    _ sourcePosition: Int,
    _ destinationRaw: Int,
    _ destinationPosition: Int,
    _ length: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) {
    outThrown?.pointee = 0

    func fail(_ throwable: Int) {
        runtimeSetThrown(outThrown, throwable)
    }

    guard sourceRaw != runtimeNullSentinelInt, destinationRaw != runtimeNullSentinelInt else {
        fail(runtimeAllocateNullPointerException(message: nil))
        return
    }
    guard let source = runtimeArrayBoxExcludingObjects(from: sourceRaw),
          let destination = runtimeArrayBoxExcludingObjects(from: destinationRaw)
    else {
        fail(runtimeAllocateArrayStoreException(message: nil))
        return
    }
    guard sourcePosition >= 0, destinationPosition >= 0, length >= 0,
          sourcePosition <= source.count, destinationPosition <= destination.count,
          length <= source.count - sourcePosition,
          length <= destination.count - destinationPosition
    else {
        fail(runtimeAllocateArrayIndexOutOfBoundsException(message: nil))
        return
    }

    let sourceKind = runtimePrimitiveArrayElementKind(rawValue: sourceRaw)
    let destinationKind = runtimePrimitiveArrayElementKind(rawValue: destinationRaw)
    switch (sourceKind, destinationKind) {
    case let (sourceKind?, destinationKind?) where sourceKind == destinationKind:
        break
    case (nil, nil):
        break
    default:
        fail(runtimeAllocateArrayStoreException(message: nil))
        return
    }

    let copiedValues = Array(source.values[sourcePosition ..< sourcePosition + length])
    if destinationKind == nil {
        let targetComponent = destination.componentType
        let sourceComponent = source.componentType
        for (offset, value) in copiedValues.enumerated() {
            guard runtimeArrayElementIsAssignable(
                value,
                sourceComponent: sourceComponent,
                to: targetComponent
            ) else {
                fail(runtimeAllocateArrayStoreException(message: nil))
                return
            }
            destination.setValue(value, at: destinationPosition + offset)
        }
    } else {
        for (offset, value) in copiedValues.enumerated() {
            destination.setValue(value, at: destinationPosition + offset)
        }
    }
}
