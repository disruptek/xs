# xs

Some random tools for my desktop environment that don't justify their own
packaging.  Build and run with `--help` to get usage hints.

## ix

A tiny tool/library to paste to http://ix.io/ -- yes, as was pointed out to me,
it's one line of `curl`. I'm going to integrate this into the bot below so it
can provide Nim Playground links automatically.

[Documentation for the ix module as generated from the source.](https://disruptek.github.io/xs/ix.html)

```
Usage:
  ix [optional-params] files to paste to ix
get, put, post, delete pastes at ix.org
Options(opt-arg sep :|=|spc):
  -h, --help                            print this cligen-erated help
  --help-syntax                         advanced: prepend,plurals,..
  --version          bool    false      print version
  -n=, --name=       string  "stdin"    default name of the input stream
  -x, --xclip        bool    true       stuff output urls into clipboard
  -e=, --extension=  string  "nim"      filename extension for content
  -r=, --reads=      int     0          remove after N reads; 0 to disable
  -g=, --get=        string  ""         retrieve a paste by id
  -p=, --put=        string  ""         update an existing paste identifier
  -d=, --delete=     string  ""         remove the given paste immediately
  -u=, --username=   string  ""         username for authentication
  --password=        string  ""         password for authentication
  -l=, --log-level=  Level   lvlNotice  specify Nim logging level
```

## Geometry

This is a little tool that I primarily use to reposition floating browser
windows precisely so that their toolbars are off-screen and their dimensions are
set exactly; some video players misbehave stupidly at magical size thresholds.

These particular requirements can usually be handled via sway config, but this
is a more general solution that I expect to grow more useful, and it's a good
demo for the swayipc library.

[Documentation for the geometry module as generated from the source.](https://disruptek.github.io/xs/geometry.html)

## Bot

This irc bot relays messages as d-bus notifications and knows how to combine
multiple consecutive messages from the same user and strip bridge prefixes. It
also avoids notifications when my irc window is focussed.

I mostly made this for interfacing with Twitch after watching @Araq struggle to
keep abreast of chat comments while streaming.

[Documentation for the bot module as generated from the source.](https://disruptek.github.io/xs/bot.html)

## AutoOpacity

This is another little demo of swayipc that I use to make my out-of-focus
terminal windows more translucent and vice-versa, as I don't use title bars or
borders and otherwise have few visual cues to indicate focus.

[Documentation for the autoopacity module as generated from the source.](https://disruptek.github.io/xs/autoopacity.html)

## KittyColor

A deprecated solution to the above problem which uses IPC to tell Kitty to
change the background color of its window. It should be obvious why I replaced
this with swayipc and autoopacity.

[Documentation for the kittycolor module as generated from the source.](https://disruptek.github.io/xs/kittycolor.html)

## License
MIT
