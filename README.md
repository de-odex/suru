suru
====

A tqdm-style progress bar in Nim

![asciicast](https://raw.githubusercontent.com/de-odex/suru/master/demo.gif)

the demo above uses this code (note that the api has since changed, refer to tests/tests.nim for updated code):
```nim
import unittest, os, sequtils, random
randomize()

test "random time test":
  for a in suru(toSeq(0..<100)):
    sleep((rand(99) + 1))

test "long time test":
  for a in suru([1, 2, 3, 5]):
    sleep(1000)

test "alternate long time test":
  sleep 1000
  var bar: SuruBar = initSuruBar(25)

  bar.start(4)

  for a in toSeq(1..1000):
    sleep 4
    if a mod 250 == 0:
      inc bar
    bar.update(50_000_000)

  bar.finish()

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

test "multi-bar test":
  echo "check if this line is removed by the bars"
  sleep 1000
  var bar: SuruBar = initSuruBar(25, 25)

  bar.start(1000, 40)

  for a in toSeq(1..1000):
    sleep 25
    inc bar
    if a mod 25 == 0:
      inc bar, 1
    bar.update(50_000_000)
    bar.update(50_000_000, 1)

  bar.finish()

  echo "check if this line is removed by the bars"
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
# pass in a positive integer if you want to change how many bars there are

bar[0].total = 3 # number of iterations

bar.setup()

for a in [20, 90, 120]:
  # do something

  inc bar # can be changed to increment n amount at a time
  # will increment all bars
  # use inc bar[0] if you only want to increment the first bar

  bar.update(50_000_000) # in nanoseconds, so the delay is 50 ms
  # will be clamped to at least 1 ms

bar.finish()
```

API Reference
-------------
TODO :(

Major To-do
-----------
the order bears no meaning

- [ ] thread-safe
- [x] multi-bar support
- [x] formatting support
  - [x] ascii-only version
  - [x] custom text
- [ ] stable api
  - might come soon, i need more opinions on the current api
- [x] iterator support
- [ ] unicode checks
- [ ] echoing within the loop
- [ ] recursive support for suru macro
  - ex: (this should work like manually making a two-bar SuruBar)
```nim
import suru

for a in suru(...):
  # do something
  for b in suru(...):
    # do another thing
```

Dependencies
------------
suru has no external Nim dependencies

