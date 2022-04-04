import std/[
  macros,
  monotimes,
  times,
  math,
  strutils,
  unicode,
  strformat
]
import ../suru

const
  prefixes* = [
    -8: "y", "z", "a", "f", "p", "n", "u", "m",
    " ",
    "k", "M", "G", "T", "P", "E", "Z", "Y"
  ]

proc fitMagnitude*(n: float): tuple[n: float, magnitude: int] =
  result = (n, 0)
  while (result.n < 0.1 or result.n > 1000) and (result.magnitude != prefixes.high or result.magnitude != prefixes.low):
    if result.n > 1000:
      result.n /= 1000
      inc result.magnitude
    elif n < 0.1:
      result.n *= 1000
      dec result.magnitude

proc formatUnit*(n: float): string =
  case n.classify
  of fcNan:
    return static: "??".align(7, ' ')
  of {fcNormal, fcSubnormal, fcZero, fcNegZero}:
    let (n, mag) = fitMagnitude(n)
    if mag == prefixes.high and n > 99:
      result = static: ">99.00Y".align(7, ' ')
    elif mag == prefixes.low and n < 0.01:
      result = static: "<0.01y".align(7, ' ')
    else:
      result = &"{n:>6.2f}" & prefixes[mag]
  of fcInf:
    result = static: ">1.00Y".align(7, ' ')
  of fcNegInf:
    result = static: "0.00".align(7, ' ')

proc formatTime*(secs: SomeFloat): string =
  if secs.classify notin {fcNormal, fcSubnormal, fcZero}:
    # if time is abnormal, output ??
    result = "  ??s"
  elif secs < 0:
    # cheat bad float subtraction by clipping anything under 0 to 0
    result = " 0.0s"
  elif secs < 100:
    # under a minute and 40 seconds, just render as seconds
    result = (secs.formatFloat(ffDecimal, 1) & "s").align(5, ' ')
  else:
    # use minute format
    let secs = secs.int
    result = ($(secs div 60)).align(2, '0') & ":" & ($(secs mod 60)).align(2, '0')


proc barDisplay*(
    ssb: SingleSuruBar,
    shaded: string,
    unshaded: string,
  ): string =
  let
    percentage = ssb.percent
    shadedCount = min(floor(percentage * ssb.length.float).int, ssb.length)
    unshadedCount = ssb.length - shadedCount

  result = newStringOfCap(ssb.length * 4)
  for _ in 0..<shadedCount:
    result &= shaded
  if shadedCount < ssb.length:
    for _ in 0..<unshadedCount:
      result &= unshaded

proc barDisplay*[N: static int](
    ssb: SingleSuruBar,
    shaded: string,
    unshaded: string,
    fractionals: array[N, string],
    alwaysShow: bool = false,
  ): string =
  let
    percentage = ssb.percent

    shadedCount = min(floor(percentage * ssb.length.float).int, ssb.length)

    fractionalIndex = block:
      if alwaysShow:
        ((percentage * ssb.length.float * fractionals.len.float).int mod fractionals.len)
      else:
        ((percentage * ssb.length.float * (fractionals.len + 1).float).int mod (fractionals.len + 1)) - 1
        # -1 when no fractional to include
        # 0..n when fractional of index n should be included

    unshadedCount = ssb.length - shadedCount - (if alwaysShow: 1 else: min(fractionalIndex + 1, 1))
    # length - shaded - (if no fractional, 0, else, 1)

  result = newStringOfCap(ssb.length * 4)
  for _ in 0..<shadedCount:
    result &= shaded
  if shadedCount < ssb.length:
    if shadedCount + unshadedCount != ssb.length:
      result &= fractionals[fractionalIndex]
    for _ in 0..<unshadedCount:
      result &= unshaded

