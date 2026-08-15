
@_cdecl("kk_list_take")
public func kk_list_take(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.prefix(clamped))))
}

@_cdecl("kk_list_drop")
public func kk_list_drop(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropFirst(clamped))))
}

@_cdecl("kk_list_takeLast")
public func kk_list_takeLast(_ listRaw: Int, _ count: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    outThrown?.pointee = 0
    if count < 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Requested element count \(count) is less than zero."
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.suffix(clamped))))
}

@_cdecl("kk_list_dropLast")
public func kk_list_dropLast(_ listRaw: Int, _ count: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let clamped = max(0, min(count, elements.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(elements.dropLast(clamped))))
}








@_cdecl("kk_list_shuffled")
public func kk_list_shuffled(_ listRaw: Int) -> Int {
    guard let _listBox = runtimeListBox(from: listRaw) else { invalidContainerPanic(#function, "list") }
    let elements = _listBox.elements
    let shuffled = elements.shuffled()
    return registerRuntimeObject(RuntimeListBox(elements: shuffled))
}
