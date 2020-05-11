suru
====

A tqdm-style progress bar in Nim

[![asciicast](https://asciinema.org/a/fLsiHgLwS8uNsGOE4wezzLL2r.svg)](https://asciinema.org/a/fLsiHgLwS8uNsGOE4wezzLL2r)
video above uses this code:
```nim
import os, sequtils, random
randomize()

for b in suru(toSeq(0..<100)):
  sleep((rand(99) + 1))
  discard

for a, b in suru([1, 2, 3, 5]):
  sleep(1000)
  discard
```

Dependencies
------------

suru has no external Nim dependencies

