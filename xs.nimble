version = "0.0.9"
author = "disruptek"
description = "xs"
license = "MIT"
requires "nim >= 0.20.0"
requires "swayipc >= 3.1.4"
requires "cligen >= 0.9.41"
requires "dbus"
requires "irc >= 0.2.1"
requires "https://github.com/disruptek/cutelog.git >= 1.0.1"
requires "bump >= 1.8.11"

bin = @["xs/bot", "xs/autoopacity", "xs/geometry", "xs/ix"]
