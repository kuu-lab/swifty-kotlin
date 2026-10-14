KUU-2036 regression fixture.

Point2D.kt is copied byte-for-byte from Todd Ginsberg's advent-2023-kotlin at revision 0d5732508025a7e340366594c879b99fe6e7cbf0:
https://github.com/tginsberg/advent-2023-kotlin/blob/0d5732508025a7e340366594c879b99fe6e7cbf0/src/main/kotlin/com/ginsberg/advent2023/Point2D.kt

Point2D.kt SHA-256: `d46de11d9bda01d4a86c1a638b6b42370989bf080b41fbd9ac9a000f14edd64c`.
The local Git attributes preserve its upstream CRLF bytes and missing final newline.

LICENSE.txt contains the upstream Apache 2.0 license. Grid.kt preserves the get-only reproducer from KUU-2036: all four direction progressions, filter/forEach, member extensions, a short-circuit while condition, and local Point2D +=. It contains no operator set, indexed assignment, or swap. Expected stdout is `done\n`, with empty stderr and exit 0.

The separate `forward_companion_initialization.kt` control uses explicit property types to isolate initialization guards from the forward computed-property inference issue KUU-2056. This fixture retains the original Point2D.kt unchanged.
