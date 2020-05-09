version = "0.0.12"
author = "disruptek"
description = "xs"
license = "MIT"
requires "nim < 2.0.0"
requires "swayipc < 4.0.0"
requires "cligen < 1.0.0"
requires "dbus"
requires "irc < 1.0.0"
requires "https://github.com/disruptek/cutelog < 2.0.0"
requires "bump < 2.0.0"
requires "https://github.com/disruptek/pulseauto < 2.0.0"

bin = @["xs/bot", "xs/autoopacity", "xs/geometry", "xs/ix", "xs/attentuate"]
