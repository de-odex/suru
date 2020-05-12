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

Usage
-----

suru can be used in two ways:
```nim
import suru

for a in suru([20, 90, 120]):
  # do something
  discard
```

or

```nim
import suru

var bar: SuruBar = initSuruBar()
# pass in a positive integer if you want to change the bar length

bar.start(3) # the length of the iterable
             # or how many iterations will happen
             # pass 0 for an unknown length

for a in [20, 90, 120]:
  # do something

  inc bar
  bar.update(50_000_000) # in nanoseconds, so the literal is 50 ms
  # you can change the delay to any delay you want

bar.finish()
```

Dependencies
------------

suru has no external Nim dependencies

