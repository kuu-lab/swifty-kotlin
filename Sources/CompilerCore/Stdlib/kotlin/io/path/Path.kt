package kotlin.io.path

import java.nio.file.Path as NioPath
import java.nio.file.Paths

public typealias Path = NioPath

public fun Path(path: String): Path = Paths.get(path)
