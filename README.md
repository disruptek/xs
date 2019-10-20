# xs

Some random tools for my desktop environment that don't justify their own
packaging.  Build and run with `--help` to get usage hints.

## Geometry

This is a little tool that I primarily use to reposition floating browser
windows precisely so that their toolbars are off-screen and their dimensions are
set exactly; some video players misbehave stupidly at magical size thresholds.

These particular requirements can usually be handled via sway config, but this
is a more general solution that I expect to grow more useful, and it's a good
demo for the swayipc library.

## Bot

This irc bot relays messages as d-bus notifications and knows how to combine
multiple consecutive messages from the same user and strip bridge prefixes. It
also avoids notifications when my irc window is focussed.

I mostly made this for interfacing with Twitch after watching @Araq struggle to
keep abreast of chat comments while streaming.

## AutoOpacity

This is another little demo of swayipc that I use to make my out-of-focus
terminal windows more translucent and vice-versa, as I don't use title bars or
borders and otherwise have few visual cues to indicate focus.

## KittyColor

A deprecated solution to the above problem which uses IPC to tell Kitty to
change the background color of its window. It should be obvious why I replaced
this with swayipc and autoopacity.

## License
MIT
