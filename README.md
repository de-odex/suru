suru
====

A tqdm-style progress bar in Nim

![asciicast](https://raw.githubusercontent.com/de-odex/suru/master/demo.gif)

the demo above uses this code:
```nim
import unittest, os, sequtils, random
randomize()

test "random time test":
  for a in suru(toSeq(0..<100)):
    sleep((rand(99) + 1))

test "long time test":
  for a in suru([1, 2, 3, 5]):
    sleep(1000)

test "constant time test":
  for a in suru(toSeq(0..<100)):
    sleep(25)

test "v-shaped time test":
  for a in suru(toSeq(1..100) & toSeq(countdown(100, 1))):
    sleep(a)

test "increasing time test":
  for a in suru(toSeq(1..100)):
    sleep(a)

test "sinusoidal time test":
  for a in suru(toSeq(1..100)):
    sleep(int(sin(a.float / 5) * 50 + 50))
```

Dependencies
------------

suru has no external Nim dependencies

