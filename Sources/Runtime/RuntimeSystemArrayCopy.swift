
// The backend declares every runtime extern as returning i64, so a Unit external
// must return a word (0) like the other Unit externals instead of C `void`.
@_cdecl("__kk_system_arraycopy")
public func kk_system_arraycopy(
    _ sourceRaw: Int,
    _ sourcePosition: Int,
    _ destinationRaw: Int,
    _ destinationPosition: Int,
    _ length: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    func fail(_ throwable: Int) -> Int {
        runtimeSetThrown(outThrown, throwable)
        return 0
    }

    guard sourceRaw != runtimeNullSentinelInt, destinationRaw != runtimeNullSentinelInt else {
        return fail(runtimeAllocateNullPointerException(message: nil))
    }
    guard let source = runtimeArrayBoxExcludingObjects(from: sourceRaw),
          let destination = runtimeArrayBoxExcludingObjects(from: destinationRaw)
    else {
        return fail(runtimeAllocateArrayStoreException(message: nil))
    }
    guard sourcePosition >= 0, destinationPosition >= 0, length >= 0,
          sourcePosition <= source.count, destinationPosition <= destination.count,
          length <= source.count - sourcePosition,
          length <= destination.count - destinationPosition
    else {
        return fail(runtimeAllocateArrayIndexOutOfBoundsException(message: nil))
    }

    let sourceKind = runtimePrimitiveArrayElementKind(rawValue: sourceRaw)
    let destinationKind = runtimePrimitiveArrayElementKind(rawValue: destinationRaw)
    switch (sourceKind, destinationKind) {
    case let (sourceKind?, destinationKind?) where sourceKind == destinationKind:
        break
    case (nil, nil):
        break
    default:
        return fail(runtimeAllocateArrayStoreException(message: nil))
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
                return fail(runtimeAllocateArrayStoreException(message: nil))
            }
            destination.setValue(value, at: destinationPosition + offset)
        }
    } else {
        for (offset, value) in copiedValues.enumerated() {
            destination.setValue(value, at: destinationPosition + offset)
        }
    }
    return 0
}
