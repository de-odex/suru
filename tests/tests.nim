import std/[unittest, os, sequtils, random, math]

import suru

randomize()

iterator temp(): int =
  while true:
    yield rand(99) + 1

suite "basic":
  test "changing total test":
    var sb = initSuruBar()
    sb.setup(0)
    for a in temp():
      if a in 1..50:
        sb[0].total += 4
      if sb[0].total != 0 and sb[0].progress >= sb[0].total:
        break
      if sb[0].total > 50:
        break
      sleep 1000
      inc sb
      sb.update(50_000_000)
    sb.finish()

  test "iterator test":
    for a in suru([2398, 981427].items):
      sleep 1000

  test "multi-bar test":
    echo "check if this line is removed by the bars"
    sleep 1000
    var sb = initSuruBar(2)
    sb.setup(1000, 40)
    for a in 1..1000:
      sleep 25
      inc sb[0]
      if a mod 25 == 0:
        inc sb[1]
      sb.update(50_000_000)
      sb.update(50_000_000, 1)
    sb.finish()
    echo "check if this line is removed by the bars"

  test "iterative bar test":
    var sb = initSuruBar(2)
    sb.setup(10, 100)
    for a in 1..10:
      sb[1].reset(a*10)
      for b in 1..a*10:
        sleep 25
        inc sb[1]
        sb.update(50_000_000)
        sb.update(50_000_000, 1)
      inc sb[0]
    sb.finish()

  test "overhead test": # use -d:suruDebug to see overhead
    var sb = initSuruBar()
    sb.setup(10_000_000)
    for a in 1..10_000_000:
      # sleep 1
      inc sb
      sb.update(8_000_000)
    sb.finish()

  test "multi-bar frame time test":
    var sb = initSuruBar(30)
    sb.setup((10_000, 30))
    for a in 1..10_000:
      # sleep 1
      inc sb
      sb.update(8_000_000)
    sb.finish()



suite "time (eta and speed)":
  # tests eta and speed statistics

  test "random time":
    for a in suru(0..<100):
      sleep((rand(99) + 1))

  test "long time":
    for a in suru([1, 2, 3, 5]):
      sleep(1000)

  test "alternate long time":
    var sb = initSuruBar()
    sb.setup(4)
    for a in 1..1000:
      sleep 5
      if a mod 250 == 0:
        inc sb
      sb.update(50_000_000)
    sb.finish()

  test "constant time":
    for a in suru(0..<100):
      sleep(25)

  test "v-shaped time":
    for a in suru(toSeq(1..100) & toSeq(countdown(100, 1))):
      sleep(a)

  test "increasing time":
    for a in suru(1..100):
      sleep(a)

  test "sinusoidal time":
    for a in suru(1..100):
      sleep(int(sin(a.float / 5) * 50 + 50))



when compileOption("threads"):
  suite "threaded":
    test "advanced":
      var sb = initSuruBarThreaded(30)
      sb.setup((100_000, 30))
      for a in 1..100_000:
        sleep 1
        inc sb
        sb.update(8_000_000)
      sb.finish()

    test "overhead": # use -d:suruDebug to see overhead
      var sb = initSuruBarThreaded()
      sb.setup(10_000_000)
      for a in 1..10_000_000:
        # sleep 1
        inc sb
        sb.update(8_000_000)
      sb.finish()
