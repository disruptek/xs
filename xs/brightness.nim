import std/os
import std/strutils

const
  DIRECTORY = "/sys/class/backlight/intel_backlight"
  BRIGHTNESS = DIRECTORY / "brightness"
  MAXIMUM = DIRECTORY / "max_brightness"

template fetch(fn: string): int =
  parseInt(strip(readFile fn))

let
  biggest = fetch(MAXIMUM)
  smallest = 1
  current = fetch(BRIGHTNESS)
  value = paramStr(1)
  future = case value:
    of "up":
      $min(current + 5, biggest)
    of "down":
      $max(current - 5, smallest)
    else:
      paramStr(1)
writeFile BRIGHTNESS, future
