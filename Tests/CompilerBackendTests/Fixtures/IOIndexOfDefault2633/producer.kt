package kuu2633

import kotlinx.io.Buffer
import kotlinx.io.Source
import kotlinx.io.write

public fun newIndexOfBuffer(): Buffer = Buffer().apply {
    write(byteArrayOf(10, 20, 30, 20))
}

public fun newIndexOfSource(): Source = Buffer().apply {
    write(byteArrayOf(10, 20, 30, 20))
}
