import std/osproc
import std/algorithm
import std/os
import std/strutils

proc renameLastStill(path: string) =
  ## rename the last still into `path`, remove all others
  var work = parentDir path
  var files: seq[string]
  for _, fn in walkDir work:
    if extractFilename(fn).startsWith "termtosvg_":
      files.add fn
  if files.len > 0:
    sort files
    moveFile files.pop, path
    while files.len > 0:
      removeFile files.pop

proc exec(s: string) =
  echo "exec: ", s
  let code = execCmd(s)
  if code != 0:
    quit code

proc temporaryFilename(): string =
  #result = staticExec """mktemp --tmpdir="$1"""" % [ getTempDir() ]
  result = getTempDir() / "demo-" & $getCurrentProcessId()

proc termToSvg(path: string; cmd: string; lines = 0; delay = 10000) =
  var lines = lines
  var animate = lines == 0
  var svg = @["--template=window_frame_powershell"]
  var work = path

  # build the binary
  var binary = temporaryFilename()
  exec cmd % [ binary ]
  svg.add """--command="$1"""" % [ binary ]

  try:
    # loop or not
    if animate:
      work = parentDir path
      svg.add "--still-frames"
      # clear any stills
      renameLastStill path
    else:
      svg.add "--loop-delay=$1" % [ $delay ]

    # calculate the ideal height
    if lines == 0:
      let (output, code) = execCmdEx binary
      # a bad exit code might be intentional
      lines = len(splitLines output) + 1 # trailing newline guard
    svg.add "--screen-geometry=80x$1" % [ $lines ]
    exec "termtosvg $1 $2" % [ work, svg.join " " ]

    if animate:
      # rename the last still into place
      renameLastStill path
  finally:
    removeFile binary

when isMainModule:
  var (output, command, lines) = (paramStr(1), paramStr(2), 0)
  if paramCount() > 2:
    lines = parseInt paramStr(3)
  echo "output: ", output, "; command: ", command, "; lines: ", lines
  termToSvg(output, command, lines = lines)
