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
	NotifyProc = proc (mtype: IrcMType; nick: string; text: string; channel: string;
		icon: NotifyIcon = OtherIcon; force: Replaces = 0): Replaces

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

proc sendNotify[T](app_name: string; replaces_id: Replaces=0; app_icon=""; summary=""; body=""; actions: seq[string]= @[]; hints: Table[string, Variant[T]]; expire_timeout: int32 = 0): Replaces =
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
	#[
	try:
		iter.advanceIter
	except:
		break
	]#

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

proc processEvent(irc: AsyncIrc; event: IrcEvent; notice: NotifyProc) {.async.} =
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
					discard event.cmd.notice(nick, text, chan, icon=SpeechIcon)
					info event.nick, "@", chan, ": ", text
				of MQuit:
					discard event.cmd.notice(event.nick, "«quit»", "", icon=QuitIcon)
					info event.nick, " quit"
				of MPart:
					chan = event.params[0]
					discard event.cmd.notice(event.nick, event.nick & "«part» " & chan, chan, icon=PartedIcon)
					info event.nick, " left " & chan
				of MJoin:
					chan = event.params[0]
					discard event.cmd.notice(event.nick, "«join» " & chan, chan, icon=JoinedIcon)
					info event.nick, " joined " & chan
				of MPong:
					#debug "pong"
					discard
				of MPing:
					#debug "ping"
					discard
				else:
					text = event.params[0]
					if event.nick != "":
						discard event.cmd.notice(event.nick, &"«{event.cmd}» " & text, text)
						debug event
		of EvConnected:
			warn "connected."
			discard
		else:
			debug event
			discard

proc bot(nick=DEFAULT_NICK;
	host=DEFAULT_HOST;
	port=DEFAULT_PORT;
	name=DEFAULT_NAME;
	pass="";
	notify="twitch";
	channels: seq[string]=DEFAULT_CHAN) =
	## this exists to define the cli arg parser;
	## it also runs our main irc loop

	let
		pass = os.getEnv("BOT_OAUTH", "")
		pno = Port(port)

	var irc: AsyncIrc

	if pass == "" and host == DEFAULT_HOST:
		error "need a password or BOT_OAUTH variable in your env"
		quit(1)

	var
		replace: Replaces = 0
		body: string
		who: string
		cmd: IrcMType

	proc notice(mtype: IrcMType; nick: string; text: string; channel: string;
		icon=OtherIcon; force: Replaces = 0): Replaces =
		let hints = {"urgency": newVariant(1'u8)}.toTable
		let newlen = nick.len + body.len + text.len
		proc saveLast(id: Replaces; newbod: string) =
			## memo'ize the last caller
			replace = id
			who = nick
			cmd = mtype
			body = newbod
		if force != 0:
			saveLast(force, text)
		elif nick == who and nick != "" and cmd == mtype and newlen < 230:
			debug "old body len ", body.len + nick.len
			saveLast(replace, body & "↵\n" & text)
			debug "new body len ", body.len + nick.len
		else:
			saveLast(0, text)

		# expire chats more slowly than other messages
		let expiry: int32 = case mtype:
			of MPrivMsg: 300_000
			else: 100_000

		result = sendNotify(notify, replaces_id=replace, app_icon= $icon,
			summary=nick, body=body, actions= @[], hints=hints,
			expire_timeout=expiry)
		# if we got a new id despite attempting to replace,
		# then we may want to re-issue with just the original text.
		if replace != 0:
			# if we made a new notice and it included prior text,
			# then just alter that notice to only include the new text.
			if result != replace and body != text:
				debug "force notice last send ", result, " and replace ", replace, " force set to ", result
				return notice(mtype, nick, text, channel, icon=icon, force=result)
			return
		# it wasn't a replacement,
		# so just set the replacement for the future.
		debug "notice last send ", result, " and replace ", replace, " result set to ", result
		replace = result

	proc eventHandler(irc: AsyncIrc; event: IrcEvent) {.async.} =
		waitfor processEvent(irc, event, notice)

	irc = newAsyncIrc(address=host, port=pno, nick=nick, user=nick,
		realname=name, serverPass=pass, joinChans=channels,
		callback=eventHandler)
	waitfor irc.run()

if isMainModule:
	let logger = newConsoleLogger(useStderr=true)
	addHandler(logger)

	dispatch bot
