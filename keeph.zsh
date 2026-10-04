# keeph: prevent macOS from sleeping for N hours (lid-close safe), then auto-restore.
#
# Commands:
#   keeph           show help (no args)
#   keeph <hours>   keep awake for N hours (integer, >=1)
#   keeph -D <hours>  same, and also keep the display on (no screen sleep/lock)
#                     (--display works too; position is free: keeph 3 -D)
#   keeph -s        show current timer and display-hold status
#   keeph -d        cancel timer and display hold, allow sleep again
#   keeph -h        show help
#
# Re-running with new <hours> while active replaces the timer (extension).
# The display hold is replaced too: re-run without -D to release it.
# The display hold is a `caffeinate -d -t <seconds>` child (no sudo needed).
# Timer survives shell exit (zsh `&!` disown).
#
# sudo NOPASSWD setup (optional, one-time, to skip password prompts):
#   echo 'taehyoungkim ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1' \
#     | sudo tee /etc/sudoers.d/pmset-keeph > /dev/null \
#     && sudo chmod 440 /etc/sudoers.d/pmset-keeph \
#     && sudo visudo -c
#   Remove with: sudo rm /etc/sudoers.d/pmset-keeph
keeph() {
  local pidfile="${TMPDIR:-/tmp}/keeph.pid"
  local dpidfile="${TMPDIR:-/tmp}/keeph-display.pid"

  # Help (no args, -h, --help)
  if [[ -z "$1" || "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
keeph - prevent macOS sleep for N hours (lid-close safe)

Usage:
  keeph <hours>      keep awake for N hours (integer, >=1)
  keeph -D <hours>   same, and also keep the display on (--display, any position)
  keeph -s           show current timer and display-hold status
  keeph -d           cancel timer and display hold, allow sleep again
  keeph -h           show this help (also shown with no args)

Examples:
  keeph 1            # 1 hour
  keeph 3            # 3 hours
  keeph 8            # long task
  keeph -D 8         # overnight run, screen stays on and unlocked

Notes:
  - Re-running with a new duration replaces the existing timer (extend).
  - Re-running without -D also releases the display hold.
  - Timer survives shell exit; on expiry sleep is restored automatically.
EOF
    return 0
  fi

  # Status: read pidfile, report remaining time
  if [[ "$1" == "-s" ]]; then
    local dpid dend
    if [[ -f "$dpidfile" ]]; then
      read -r dpid dend < "$dpidfile"
    fi
    local dmsg="Display hold: off."
    if [[ -n "$dpid" ]] && kill -0 "$dpid" 2>/dev/null; then
      dmsg="Display hold: on (PID $dpid), ends $(date -r "$dend" '+%H:%M')."
    fi
    if [[ ! -f "$pidfile" ]]; then
      echo "No active timer."
      echo "$dmsg"
      return 0
    fi
    local pid end_epoch
    read -r pid end_epoch < "$pidfile"
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
      echo "No active timer (stale pidfile)."
      echo "$dmsg"
      return 0
    fi
    local now=$(date +%s)
    local remain=$(( end_epoch - now ))
    if (( remain <= 0 )); then
      echo "Active timer (PID $pid): expiring now."
    else
      local h=$(( remain / 3600 ))
      local m=$(( (remain % 3600) / 60 ))
      echo "Active timer (PID $pid): ${h}h ${m}m remaining, ends $(date -r "$end_epoch" '+%H:%M')."
    fi
    echo "$dmsg"
    return 0
  fi

  # Disable: cancel timer and allow sleep again
  if [[ "$1" == "-d" ]]; then
    if [[ -f "$pidfile" ]]; then
      local pid
      pid=$(awk '{print $1}' "$pidfile")
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "Timer cancelled."
      else
        echo "No active timer (cleaning up pidfile)."
      fi
      rm -f "$pidfile"
    else
      echo "No active timer."
    fi
    _keeph_release_display "$dpidfile"
    sudo pmset -a disablesleep 0
    echo "Sleep allowed again."
    return 0
  fi

  # Run: validate <hours>
  local hours="" display=0 arg
  for arg in "$@"; do
    case "$arg" in
      -D|--display) display=1 ;;
      *) if [[ -z "$hours" ]]; then hours="$arg"; else hours="invalid"; fi ;;
    esac
  done
  if ! [[ "$hours" =~ ^[0-9]+$ ]] || (( hours < 1 )); then
    echo "Error: <hours> must be an integer >= 1." >&2
    echo "Run 'keeph -h' for usage." >&2
    return 1
  fi

  # Replace existing timer if any
  if [[ -f "$pidfile" ]]; then
    local prev_pid
    prev_pid=$(awk '{print $1}' "$pidfile")
    if [[ -n "$prev_pid" ]] && kill -0 "$prev_pid" 2>/dev/null; then
      kill "$prev_pid" 2>/dev/null
      echo "Previous timer cancelled, extending..."
    fi
  fi
  _keeph_release_display "$dpidfile"

  local seconds=$(( hours * 3600 ))
  if ! sudo pmset -a disablesleep 1; then
    echo "Error: failed to disable sleep (sudo or pmset issue)." >&2
    return 1
  fi
  local end_epoch=$(( $(date +%s) + seconds ))
  echo "Awake for ${hours}h, sleep allowed again at $(date -r "$end_epoch" '+%H:%M')."
  (sleep "$seconds" && sudo pmset -a disablesleep 0 && rm -f "$pidfile") &!
  echo "$! $end_epoch" > "$pidfile"

  if (( display )); then
    caffeinate -d -t "$seconds" &!
    echo "$! $end_epoch" > "$dpidfile"
    echo "Display stays on until the same time."
  fi
}

# Stop the display-hold caffeinate (if any) and remove its pidfile.
_keeph_release_display() {
  local dpidfile="$1" dpid
  [[ -f "$dpidfile" ]] || return 0
  dpid=$(awk '{print $1}' "$dpidfile")
  if [[ -n "$dpid" ]] && kill -0 "$dpid" 2>/dev/null; then
    kill "$dpid" 2>/dev/null
    echo "Display hold released."
  fi
  rm -f "$dpidfile"
}
