func runtimeElementToString(_ elem: Int) -> String {
    if elem == runtimeNullSentinelInt {
        return "null"
    }
    if let description = runtimeFunctionDescription(elem) {
        return description
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: elem) else {
        return "\(elem)"
    }
    // KUU-1352: coroutine job/task handles live in the liveness registry, not
    // objectPointers — render kotlinx's `Name{State}@hex` before the
    // pointer-type gate drops them into the numeric fallback.
    if let rendered = runtimeJobHandleDebugString(elem) {
        return rendered
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return "\(elem)"
    }
    if let dispatcher = tryCast(ptr, to: RuntimeDispatcher.self),
       let name = dispatcher.displayName {
        return name
    }
    if let range = tryCast(ptr, to: RuntimeRangeBox.self) {
        return runtimeRangeToString(range)
    }
    if let override = runtimeAnyToStringOverride(elem),
       let pointer = extractString(from: override)
    {
        return pointer
    }
    if runtimeIsUnitBox(elem) {
        return "kotlin.Unit"
    }
    if let stringBox = tryCast(ptr, to: RuntimeStringBox.self) {
        return stringBox.value
    }
    if let intBox = tryCast(ptr, to: RuntimeIntBox.self) {
        return intBox.enumEntryName ?? "\(intBox.value)"
    }
    if let boolBox = tryCast(ptr, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
        return "\(longBox.value)"
    }
    if let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
        return "\(UInt(bitPattern: ulongBox.value))"
    }
    if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
        return runtimeFormatFloatingPoint(floatBox.value)
    }
    if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
        return runtimeFormatFloatingPoint(doubleBox.value)
    }
    if let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
        return runtimeCharacterFromRaw(charBox.value)
    }
    if let override = runtimeAnyToStringOverrideText(elem) {
        return override
    }
    if let throwableString = runtimeThrowableToString(elem) {
        return throwableString
    }
    if let instantBox = tryCast(ptr, to: RuntimeInstantBox.self) {
        return runtimeInstantToString(instantBox)
    }
    if let localeBox = tryCast(ptr, to: RuntimeLocaleBox.self) {
        return runtimeLocaleToString(localeBox)
    }
    if let listBox = runtimeListBox(from: elem) {
        let parts = listBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let setBox = tryCast(ptr, to: RuntimeSetBox.self) {
        let parts = setBox.values.map { runtimeElementToString($0) }
        return "[" + parts.joined(separator: ", ") + "]"
    }
    if let mapBox = tryCast(ptr, to: RuntimeMapBox.self) {
        let parts = zip(mapBox.keyValues, mapBox.entryValues).map { key, value in
            "\(runtimeElementToString(key))=\(runtimeElementToString(value))"
        }
        return "{" + parts.joined(separator: ", ") + "}"
    }
    if let pairBox = tryCast(ptr, to: RuntimePairBox.self) {
        let first = runtimeElementToString(pairBox.firstValue)
        let second = runtimeElementToString(pairBox.secondValue)
        if runtimeIsMapEntry(rawValue: elem) {
            return "\(first)=\(second)"
        }
        if runtimeObjectTypeID(rawValue: elem) == indexedValueRuntimeTypeID {
            return "IndexedValue(index=\(first), value=\(second))"
        }
        return "(\(first), \(second))"
    }
    if let tripleBox = tryCast(ptr, to: RuntimeTripleBox.self) {
        let first = runtimeElementToString(tripleBox.firstValue)
        let second = runtimeElementToString(tripleBox.secondValue)
        let third = runtimeElementToString(tripleBox.thirdValue)
        return "(\(first), \(second), \(third))"
    }
    if let rangeBox = tryCast(ptr, to: RuntimeRangeBox.self) {
        let first = runtimeElementToString(rangeBox.first)
        let last = runtimeElementToString(rangeBox.last)
        if !rangeBox.kind.isProgression {
            return "\(first)..\(last)"
        } else if rangeBox.step == -1 {
            return "\(first) downTo \(last) step 1"
        } else if rangeBox.step < 0 {
            return "\(first) downTo \(last) step \(-rangeBox.step)"
        } else {
            return "\(first)..\(last) step \(rangeBox.step)"
        }
    }
    if let rangeBox = tryCast(ptr, to: RuntimeDoubleRangeBox.self) {
        let separator = rangeBox.endExclusive ? "..<" : ".."
        return "\(runtimeFormatFloatingPoint(rangeBox.first))\(separator)\(runtimeFormatFloatingPoint(rangeBox.last))"
    }
    if let rangeBox = tryCast(ptr, to: RuntimeFloatRangeBox.self) {
        let separator = rangeBox.endExclusive ? "..<" : ".."
        return "\(runtimeFormatFloatingPoint(rangeBox.first))\(separator)\(runtimeFormatFloatingPoint(rangeBox.last))"
    }
    if let arrayBox = tryCast(ptr, to: RuntimeArrayBox.self), type(of: arrayBox) == RuntimeArrayBox.self {
        return runtimeFloatingPointArrayToString(elem, box: arrayBox) ?? runtimeArrayIdentityToString(elem)
    }
    if let sbBox = tryCast(ptr, to: RuntimeStringBuilderBox.self) {
        return sbBox.stringValue
    }
    // kotlin.concurrent(.atomics).AtomicReference.toString() renders the
    // current value, matching the JDK AtomicReference it is modelled on.
    if let atomicRefBox = tryCast(ptr, to: AtomicRefBox.self) {
        return runtimeElementToString(atomicRefBox.load())
    }
    if let kclassBox = tryCast(ptr, to: RuntimeKClassBox.self) {
        return runtimeKClassToString(kclassBox)
    }
    if let ktypeProjectionBox = tryCast(ptr, to: RuntimeKTypeProjectionBox.self) {
        return runtimeKTypeProjectionToString(ktypeProjectionBox)
    }
    if let ktypeBox = tryCast(ptr, to: RuntimeKTypeBox.self) {
        return runtimeKTypeToString(ktypeBox)
    }
    if let rendered = runtimeRenderIndexedValueObject(elem, render: runtimeElementToString) {
        return rendered
    }
    if let resultBox = tryCast(ptr, to: RuntimeResultBox.self) {
        return runtimeResultToString(resultBox, render: runtimeElementToString)
    }
    // KUU-1352: a bound Job wrapper box (Job()/SupervisorJob()/
    // CompletableDeferred/JobSupport subclass). Runs after the Any.toString
    // override checks so a declared override still wins.
    if let rendered = runtimeJobWrapperDebugString(elem) {
        return rendered
    }
    // Registered object of a type this renderer does not know: keep it
    // recognisable as an object instead of leaking its address as a number,
    // matching `runtimeRenderAnyForPrint`.  Non-object handles already
    // returned their numeric value above.
    return "<object \(ptr)>"
}

func runtimeElementToString(_ value: RuntimeValue) -> String {
    switch value.tag {
    case RuntimeValue.stringTag:
        guard let data = UnsafePointer<UInt8>(bitPattern: value.payload0) else {
            return "null"
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    case RuntimeValue.charTag:
        return runtimeCharacterFromRaw(value.payload0)
    default:
        return runtimeElementToString(value.payload0)
    }
}
