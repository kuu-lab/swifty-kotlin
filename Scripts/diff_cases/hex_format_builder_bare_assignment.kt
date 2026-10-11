// Proposed source/artifact routing regression. Not compiled or executed in this review.
fun main() {
    val format = HexFormat {
        bytes {
            bytesPerLine = 5
            bytesPerGroup = 2
            bytePrefix = "["
            byteSuffix = "]"
            var lineRejected = false
            try {
                bytesPerLine = 0
            } catch (failure: IllegalArgumentException) {
                lineRejected = true
            }
            println(lineRejected)
            println(bytesPerLine)
            var prefixRejected = false
            try {
                bytePrefix = "\n"
            } catch (failure: IllegalArgumentException) {
                prefixRejected = true
            }
            println(prefixRejected)
            println(bytePrefix)
        }
    }
    println(format.bytes.bytesPerLine)
    println(format.bytes.bytePrefix)
    println(byteArrayOf(1, 2).toHexString(format))
}
