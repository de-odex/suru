import macros, std/monotimes, times, terminal, math, strutils, sequtils, unicode, strformat
{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = distinct float
  SingleSuruBar* = object
    length*: int
    progress: int
    total: int
    barStr: string
    progressStat: ExpMovingAverager
    timeStat: ExpMovingAverager
    startTime: MonoTime
    lastIncrement: MonoTime
    currentAccess: MonoTime
    lastAccess: MonoTime
    lastProgress: int
  SuruBar* = object
    bars: seq[SingleSuruBar]
    currentIndex: int # for usage in show(), tracks current index cursor is on relative to first progress bar

const
  fractionals = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
  prefixes = ["", "k", "M", "G", "T", "P", "E", "Z"] # Y is omitted, max is 1Y

proc incMagnitude(n: float, magnitude: int): (float, int) =
  if n > 1000:
    result = (n / 1000, magnitude + 1)
  else:
    result = (n, magnitude)

proc highestMagnitude(n: float): (float, int) =
  result = (n, 0)
  var new = incMagnitude(result[0], result[1])
  while result != new and new[1] <= prefixes.high:
    result = new
    new = incMagnitude(result[0], result[1])

proc formatUnit*(n: float): string =
  case n.classify
  of fcNan:
    return static: "??".align(6, ' ')
  of {fcNormal, fcSubnormal, fcZero, fcNegZero}:
    let (n, mag) = highestMagnitude(n)
    if n < 1_000:
      result = (n.formatFloat(ffDecimal, 2) & prefixes[mag]).align(6, ' ')
    else:
      result = static: ">1.00Y".align(6, ' ')
  of fcInf:
    result = static: ">1.00Y".align(6, ' ')
  of fcNegInf:
    result = static: "0.00".align(6, ' ')

proc formatTime(secs: SomeFloat): string =
  if secs.classify notin {fcNormal, fcSubnormal, fcZero}:
    # if time is abnormal, output ??
    result = "  ??s"
  elif secs < 0:
    # cheat bad float subtraction by clipping anything under 0 to 0
    result = " 0.0s"
  elif secs <= 100:
    # under a minute and 40 seconds, just render as seconds
    result = (secs.formatFloat(ffDecimal, 1) & "s").align(5, ' ')
  else:
    # use minute format
    let secs = secs.int
    result = ($(secs div 60)).align(2, '0') & ":" & ($(secs mod 60)).align(2, '0')

#

const alpha = exp(-1/5)

proc push(mv: var ExpMovingAverager, value: float) =
  if mv.float == 0:
    mv = value.ExpMovingAverager
  else:
    mv = (value + alpha * (mv.float - value)).ExpMovingAverager

proc push(mv: var ExpMovingAverager, value: int) =
  mv.push(value.float)

#

proc initSingleSuruBar*(length: int): SingleSuruBar =
  SingleSuruBar(
    length: length,
    #progress: 0,
      #total: 0,
    barStr: &"{0:>3}%|" & " ".repeat(length) & "| " & "0/0",
    #progressStat: 0.ExpMovingAverager,
    #timeStat: 0.ExpMovingAverager,
    #startTime: MonoTime(),
    #lastIncrement: MonoTime(),
    #currentAccess: MonoTime(),
    #lastAccess: MonoTime(),
    #lastProgress: 0,
  )

proc initSuruBar*(bars: int = 1): SuruBar =
  ## Creates a SuruBar with the given amount of bars
  ## Does not prime the bar for a loop, use ``setup`` for that
  SuruBar(
    bars: initSingleSuruBar(25).repeat(bars),
  )

iterator items*(sb: SuruBar): SingleSuruBar =
  for bar in sb.bars:
    yield bar

iterator mitems*(sb: var SuruBar): var SingleSuruBar =
  var index: int
  while index < sb.bars.len:
    yield sb.bars[index]
    inc(index)

iterator pairs*(sb: SuruBar): (int, SingleSuruBar) =
  var index: int
  while index < sb.bars.len:
    yield (index, sb.bars[index])
    inc(index)

proc `[]`*(bar: SuruBar, index: Natural): SingleSuruBar =
  bar.bars[index]

proc `[]`*(bar: var SuruBar, index: Natural): var SingleSuruBar =
  bar.bars[index]

proc inc*(bar: var SingleSuruBar) =
  ## Increments the bar progress
  inc bar.progress
  let
    percentage = bar.progress / bar.total
    shaded = floor(percentage * bar.length.float).int
    fractional = (percentage * bar.length.float * 8).int mod 8
    unshaded = bar.length - shaded - (if fractional == 0: 0 else: 1)
    totalStr = $bar.total

  # TODO: improve the algorithm
  if shaded < bar.length:
    bar.barStr = "█".repeat(shaded) & fractionals[fractional] & " ".repeat(unshaded)
  elif shaded == bar.length:
    bar.barStr = "█".repeat(shaded)
  bar.barStr = &"{(percentage*100).round.int:>3}%|" &
    bar.barStr & "| " &
    ($bar.progress).align(totalStr.len, ' ') & "/" & totalStr

  let newTime = getMonoTime()
  bar.timeStat.push (newTime.ticks - bar.lastIncrement.ticks).int div 1_000_000
  bar.lastIncrement = newTime
  bar.progressStat.push bar.progress - bar.lastProgress
  bar.lastProgress = bar.progress

proc inc*(sb: var SuruBar) =
  ## Increments the bar progress
  for bar in sb.mitems:
    inc bar

proc `$`(bar: SingleSuruBar): string =
  let
    perSec = bar.progressStat.float * (1000/bar.timeStat.float)
    timeElapsed = (bar.currentAccess.ticks - bar.startTime.ticks).float / 1_000_000_000
    timeLeft = (bar.total - bar.progress).float / perSec -
      ((getMonoTime().ticks - bar.lastIncrement.ticks).float / 1_000_000_000)

  result = bar.barStr &
    " [" & timeElapsed.formatTime & "<" & timeLeft.formatTime & ", " & perSec.formatUnit & "/sec]"

  when defined(suruDebug):
    result &= " " & ((getMonoTime().ticks - bar.currentAccess.ticks).float/1_000).formatFloat(ffDecimal, 2) & "us overhead"

proc moveCursor(sb: var SuruBar, index: int = 0) =
  let difference = index - sb.currentIndex
  if difference < 0:
    stdout.cursorUp(abs(difference))
  elif difference > 0:
    stdout.cursorDown(abs(difference))
  sb.currentIndex = index

proc show(bar: var SingleSuruBar) =
  ## Shows the sb in a formatted style.
  when defined(windows):
    stdout.eraseLine()
    stdout.write($bar)
  else:
    stdout.write("\e[2K", $bar)
  stdout.flushFile()
  stdout.setCursorXPos(0)

proc reset*(bar: var SingleSuruBar, iterableLength: int) =
  ## Resets the bar to an empty bar, not including its length and total.
  let now = getMonoTime()
  bar.progress = 0
  bar.total = iterableLength
  bar.barStr = &"{0:>3}%|" &
    " ".repeat(bar.length) & "| " & "0".align(($bar.total).len, ' ') &
    "/" & ($bar.total)
  bar.progressStat = 0.ExpMovingAverager
  bar.timeStat = 0.ExpMovingAverager
  bar.startTime = now
  bar.lastIncrement = now
  bar.currentAccess = now
  bar.lastAccess = now
  bar.lastProgress = 0

proc setup*(sb: var SuruBar, iterableLengths: varargs[int]) =
  # sets certain fields more properly now that the iterable length is known
  doAssert iterableLengths.len == sb.bars.len

  for index in 1..<iterableLengths.len:
    echo ""
  if iterableLengths.len > 1:
    stdout.cursorUp(iterableLengths.len - 1)

  for index, iterableLength in iterableLengths:
    sb[index].total = iterableLength
    sb[index].barStr = &"{0:>3}" & "%|" & " ".repeat(sb[index].length) & "| " & "0".align(($sb[index].total).len, ' ') & "/" & $sb[index].total
    sb[index].startTime = getMonoTime()
    sb[index].currentAccess = sb[index].startTime
    sb[index].lastAccess = sb[index].startTime
    sb[index].lastIncrement = sb[index].startTime
    sb[index].timeStat.push 0
    sb[index].progressStat.push 0
    sb.moveCursor(index)
    sb[index].show()

proc setup*(sb: var SuruBar, iterableLengthsAndAmounts: varargs[(int, int)]) =
  sb.setup((@iterableLengthsAndAmounts).foldl(a & b[0].repeat(b[1]), newSeq[int]()))

proc start*(sb: var SuruBar, iterableLengths: varargs[int]) {.deprecated: "Deprecated, use ``setup``".} =
  sb.setup(iterableLengths)

proc start*(sb: var SuruBar, iterableLengthsAndAmounts: varargs[(int, int)]) {.deprecated: "Deprecated, use ``setup``".} =
  sb.setup(iterableLengthsAndAmounts)

proc update*(sb: var SuruBar, delay: int = 8_000_000, index: int = -1) =
  template update {.dirty.} =
    let
      difference = newTime.ticks - sb[index].lastAccess.ticks # in nanoseconds
    if difference > max(delay, 1_000_000): # in nanoseconds
      sb[index].currentAccess = newTime
      sb.moveCursor(index)
      sb[index].show()
      sb[index].lastAccess = newTime
  let
    newTime = getMonoTime()
  if index < 0:
    for index, _ in sb:
      update()
  else:
    update()

proc finish*(sb: var SuruBar) =
  for index, _ in sb:
    sb.moveCursor(index)
    sb[index].show()
  echo ""

#

template len(x: typedesc[array]): int =
  system.len(x)

template len[N, T](x: array[N, T]): int =
  system.len(x)

template len(arg: untyped): int =
  0

macro suru*(x: ForLoopStmt): untyped =
  ## Wraps an iterable for printing a progress bar
  ## WARNING: Does not work for iterators
  expectKind x, nnkForStmt

  let
    bar = genSym(nskVar, "bar")
    toIterate = genSym(nskVar, "toIterate")
    a = x[^2][1]

  result = newStmtList()

  # first printing of the progress bar
  result.add quote do:
    var
      `bar`: SuruBar = initSuruBar()
      `toIterate` = `a`

    `bar`.setup(len(`toIterate`))

  var body = x[^1]
  # makes body a statement list to be able to add statements
  if body.kind != nnkStmtList:
    body = newTree(nnkStmtList, body)

  # in-loop printing of the progress bar
  body.add quote do:
    inc `bar`
    `bar`.update(50_000_000)

  # re-adds the variables into the new for statement
  var newFor = newTree(nnkForStmt)
  for i in 0..<x.len-2:
    newFor.add x[i]

  # transforms suru(...) to '...'
  newFor.add toIterate
  newFor.add body
  result.add newFor

  # wraps the whole macro in a block to create a new scope
  # also includes final print of the bar
  result = quote do:
    block:
      `result`
      `bar`.finish()

when isMainModule:
  import unittest, os, sequtils, random
  randomize()

  test "random time test":
    for a in suru(0..<100):
      sleep((rand(99) + 1))

  test "long time test":
    for a in suru([1, 2, 3, 5]):
      sleep(1000)

  test "alternate long time test":
    var sb: SuruBar = initSuruBar(25)
    sb.setup(4)
    for a in 1..1000:
      sleep 5
      if a mod 250 == 0:
        inc sb
      sb.update(50_000_000)
    sb.finish()

  test "constant time test":
    for a in suru(0..<100):
      sleep(25)

  test "v-shaped time test":
    for a in suru(toSeq(1..100) & toSeq(countdown(100, 1))):
      sleep(a)

  test "increasing time test":
    for a in suru(1..100):
      sleep(a)

  test "sinusoidal time test":
    for a in suru(1..100):
      sleep(int(sin(a.float / 5) * 50 + 50))

  test "multi-bar test":
    echo "check if this line is removed by the bars"
    sleep 1000
    var sb: SuruBar = initSuruBar(25, 25)
    sb.setup(1000, 40)
    for a in 1..1000:
      sleep 25
      inc sb
      if a mod 25 == 0:
        inc sb[1]
      sb.update(50_000_000)
      sb.update(50_000_000, 1)
    sb.finish()
    echo "check if this line is removed by the bars"

  test "iterative bar test":
    var sb: SuruBar = initSuruBar(25, 25)
    sb.setup(10, 100)
    for a in 1..10:
      sb[1].reset(a*10)
      for b in 1..a*10:
        sleep 25
        inc sb[1]
        sb.update(50_000_000)
        sb.update(50_000_000, 1)
      inc sb
    sb.finish()

  test "overhead test": # use -d:suruDebug to see overhead
    var sb: SuruBar = initSuruBar(25)
    sb.setup(10_000_000)
    for a in 1..10_000_000:
      # sleep 1
      inc sb
      sb.update(8_000_000)
    sb.finish()

  test "multi-bar frame time test":
    var sb: SuruBar = initSuruBar((25, 30))
    sb.setup((10_000, 30))
    for a in 1..10_000:
      # sleep 1
      incAll sb
      sb.updateAll(8_000_000)
    sb.finish()
