#? replace(sub = "\t", by = " ")
import os
import re
import irc
import cligen
import asyncdispatch
import asyncfutures
import times
import notify
import dbus
import tables
import strformat
import logging

const DEFAULT_NICK = "disruptek"
const DEFAULT_NAME = "Andy Davidoff"
const DEFAULT_HOST = "irc.chat.twitch.tv"
const DEFAULT_PORT = 6667
#const DEFAULT_CHAN = @["#" & DEFAULT_NICK]
const DEFAULT_CHAN = @[]

type
	Replaces = uint32
	Memo = object
		app: string
		summary: string
		body: string
		replace: Replaces
		toolong: int
	NotifyIcon = enum NoIcon = "",
		ChatIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5e8.png", # 🗨️
		EjectIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23cf.png", # ⏏️
		PlayIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u25b6.png", # ▶️
		StopIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f9.png", # ⏹️
		ShuffleIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f500.png", # 🔀
		RepeatIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f501.png", # 🔁
		RecordIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23fa.png", # ⏺️
		JoinedIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23fa.png", # ⏺️
		PauseIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f8.png", # ⏸️
		PartedIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f8.png", # ⏸️
		QuitIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u26d4.png", # ⛔
		OtherIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u2753.png", # ❓
		QuestionIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u2754.png", # ❔
		StatementIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ac.png", # 💬
		ThoughtIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ad.png", # 💭
		AngerIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5ef.png", # 🗯️
		SpeechIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ac.png", # 💬
		LoudIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4e2.png", # 📢
		TalkIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5e3.png", # 🗣️

#[

INT32 org.freedesktop.Notifications.Notify (	app_name,
	replaces_id,
	app_icon,
	summary,
	body,
	actions,
	hints,
	expire_timeout);
STRING app_name;
UINT32 replaces_id;
STRING app_icon;
STRING summary;
STRING body;
ARRAY actions;
DICT hints;
INT32 expire_timeout;

]#

proc sendNotify[T](app_name: string; replaces_id: Replaces=0; app_icon="";
	summary=""; body=""; actions: seq[string]= @[];
	hints: Table[string, Variant[T]]; expire_timeout: int32 = 0): Replaces =
	## send a dbus message for notification purposes

	# this is straight outta solitudesf's example in dbus
	let bus = getBus(DBUS_BUS_SESSION)
	var msg = makeCall("org.freedesktop.Notifications",
		ObjectPath("/org/freedesktop/Notifications"),
		"org.freedesktop.Notifications",
		"Notify")

	msg.append(app_name)
	msg.append(replaces_id)
	msg.append(app_icon)
	msg.append(summary)
	msg.append(body)
	msg.append(actions)
	msg.append(hints)
	msg.append(expire_timeout)

	let
		pending = bus.sendMessageWithReply(msg)
		reply = pending.waitForReply()
	var
		iter = reply.iterate()
		value = iter.unpackCurrent(DbusValue)
	result = value.asNative(Replaces)

proc stripSource(nick: var string; text: var string) =
	## transform the nick if it came from gitter/discord
	var
		singly = nick & text
		pattern = re"^From(Gitter|Discord)[^<]*<([^>]+)>[^ ]* (.*)$"
		matches: array[3, string]

	if not singly.match(pattern, matches):
		return
	nick = matches[^2]
	text = matches[^1]

proc notify(memo: var Memo; summary: string; body: string; icon=OtherIcon; expiry: int32 = -1) =
	let hints = {"urgency": newVariant(1'u8)}.toTable

	# never re-use the last notification if the summary doesn't match
	if summary != memo.summary:
		memo.replace = 0
		memo.body = body
		memo.summary = summary

	# maybe just update the last notification
	while memo.replace != 0:
		let newlen = summary.len + memo.body.len + body.len
		if newlen > memo.toolong:
			# it's too long to update
			memo.replace = 0
			memo.body = body
			break
		# maybe append a chat separator
		if memo.body.len > 0:
			memo.body &= "↵\n"
		memo.body &= body
		break

	let lastid = sendNotify(memo.app, replaces_id=memo.replace, app_icon= $icon,
		summary=summary, body=memo.body, actions= @[], hints=hints,
		expire_timeout=expiry)
	# were we trying to replace?  yes?
	if memo.replace != 0:
		# did it work?  no?
		if lastid != memo.replace:
			# empty the stashed body; we'll just add the new one to ""
			memo.body = ""
			# replace the last notification with one having just the current body
			memo.replace = lastid
			memo.notify(summary, body, icon=icon, expiry=expiry)
			# return here to ensure we don't mess with state
			return
	# stash the last id for next time
	memo.replace = lastid


proc bot(nick=DEFAULT_NICK;
	host=DEFAULT_HOST;
	port=DEFAULT_PORT;
	name=DEFAULT_NAME;
	pass="";
	notify="twitch";
	toolong=230;
	channels: seq[string]=DEFAULT_CHAN) =
	## this exists to define the cli arg parser;
	## it also runs our main irc loop

	let
		pass = os.getEnv("BOT_OAUTH", "")
		pno = Port(port)

	var
		irc: AsyncIrc
		memo = Memo(app: notify, toolong: toolong)

	if pass == "" and host == DEFAULT_HOST:
		error "need a password or BOT_OAUTH variable in your env"
		quit(1)

	proc eventHandler(irc: AsyncIrc; event: IrcEvent) {.async.} =
		## the client runs this callback whenever an event comes in;
		## eg. a chat event, a server event, a channel event, etc.
		var
			chan, nick, text: string
		case event.typ:
			of EvDisconnected:
				warn "disconnected; reconnecting..."
				discard irc.reconnect()
			of EvMsg:
				case event.cmd:
					of MPrivMsg:
						(chan, text) = (event.params[0], event.params[1])
						nick = event.nick
						stripSource(nick, text)
						if "ACTION" in text:
							debug event
						memo.notify(nick, text, icon=SpeechIcon, expiry=300_000)
						info event.nick, "@", chan, ": ", text
					of MQuit:
						memo.notify(event.nick, "«quit»", icon=QuitIcon, expiry=100_000)
						info event.nick, " quit"
					of MPart:
						chan = event.params[0]
						memo.notify(event.nick, &"«part» {chan}", icon=PartedIcon, expiry=100_000)
						info event.nick, " left " & chan
					of MJoin:
						chan = event.params[0]
						memo.notify(event.nick, &"«join» {chan}", icon=JoinedIcon, expiry=100_000)
						info event.nick, " joined " & chan
					of MNotice:
						(chan, text) = (event.params[0], event.params[1])
						memo.notify(event.nick, &"«{chan}» {text}", expiry=100_000)
						info event.nick, "@", chan, ": ", text
					of MPong:
						#debug "pong"
						discard
					of MPing:
						#debug "ping"
						discard
					else:
						text = event.params[0]
						if event.nick != "":
							memo.notify(event.nick, &"«{event.cmd}» " & text, expiry=100_000)
							debug event
			of EvConnected:
				warn "connected."
			else:
				debug event

	irc = newAsyncIrc(address=host, port=pno, nick=nick, user=nick,
		realname=name, serverPass=pass, joinChans=channels,
		callback=eventHandler)
	waitfor irc.run()

when isMainModule:
	let logger = newConsoleLogger(useStderr=true)
	addHandler(logger)

	dispatch bot
