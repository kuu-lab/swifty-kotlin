# Parser star projection regression (KUU-1930)

`ParserResult.kt`, `Parser.kt`, `Map.kt`, and `Consumer.kt` are unchanged copies
from [y9san9/kotlin-simple-json](https://github.com/y9san9/kotlin-simple-json/tree/bc25b4548c9da0d655fe8ac1001321aa85bf1ad2),
revision `bc25b4548c9da0d655fe8ac1001321aa85bf1ad2`, under `src/main/kotlin/parser/base/`.
The upstream MIT license is included in `LICENSE`.

`Main.kt` is the independent consumer. Expected stdout:

```text
Success(value=kotlin.Unit, remaining=tail)
```
