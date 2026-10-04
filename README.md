# keeph

**Keep your Mac awake for exactly N hours. Then forget about it.**

Long builds. Overnight transcodes. AI agents grinding through a queue. You close the lid for a coffee — your Mac sleeps and your job dies. You crack open System Settings, hunt for the right toggle, leave it on, then forget about it for three days. Battery cooked. Fan screaming. Bad time.

`keeph` is a one-line zsh function that does exactly the right thing: disable sleep for the hours you specify, then **automatically re-enable it** when the timer expires — even if you close the lid, walk away, or never touch the terminal again.

```bash
keeph 3        # awake for 3 hours, then auto-restore
keeph 8        # long task
keeph -D 8     # long task, screen stays on and unlocked
keeph -s       # how much time is left?
keeph -d       # never mind, allow sleep again
```

## Why not just `caffeinate`?

`caffeinate` ties the awake state to a foreground process or a fixed `-t` timeout that dies with your shell. Lid-close still puts the Mac to sleep on most setups. `keeph` flips the system-level `pmset disablesleep` flag, so **closing the lid keeps the machine running**, and a backgrounded timer restores normal behavior on schedule — surviving terminal exits, ssh disconnects, and tab closures.

## Install

### Homebrew (recommended)

```bash
brew tap ww-w-ai/tap
brew install keeph
```

### Manual

```bash
curl -fsSL https://raw.githubusercontent.com/ww-w-ai/keeph/main/keeph.zsh -o ~/.config/zsh/keeph.zsh
echo 'source ~/.config/zsh/keeph.zsh' >> ~/.zshrc
```

Or auto-source everything in `~/.config/zsh`:

```zsh
# in ~/.zshrc
for f in ~/.config/zsh/*.zsh(N); do source "$f"; done
```

## Usage

```
keeph <hours>      keep the Mac awake for N hours (integer, >= 1)
keeph -D <hours>   same, and also keep the display on (--display, any position)
keeph -s           show current timer and display-hold status
keeph -d           cancel the timer and display hold, allow sleep again
keeph -h           show help (also shown with no args)
```

Re-running with a new duration **replaces** the existing timer — handy when a job runs longer than expected. The timer survives shell exit and ssh disconnect.

### Keep the display on

`pmset disablesleep` stops system sleep and lid-close sleep. It does not stop the display from turning off, and a sleeping display can lock the screen. That breaks unattended jobs that need a visible, unlocked desktop, such as browser automation overnight.

`keeph -D 8` does everything `keeph 8` does and also starts `caffeinate -d -t 28800` for the same 8 hours. `caffeinate` needs no `sudo`.

- `keeph -s` prints the display-hold state and its end time next to the timer status.
- `keeph -d` cancels both the timer and the display hold.
- Re-running `keeph <hours>` replaces both. Run it without `-D` to release the display hold.
- If your lock settings require a password after the screen saver or display sleep, keeping the display on also avoids that lock. A manual lock (Ctrl+Cmd+Q) still locks the screen.

## Skip the password prompt

`pmset` requires `sudo`. To avoid typing your password every time, allow it passwordless for this one command:

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" \
  | sudo tee /etc/sudoers.d/pmset-keeph > /dev/null \
  && sudo chmod 440 /etc/sudoers.d/pmset-keeph \
  && sudo visudo -c
```

Remove later with: `sudo rm /etc/sudoers.d/pmset-keeph`

## Requirements

- macOS (uses `pmset`)
- zsh (uses `&!` for disowned background timer)

## License

MIT — see [LICENSE](LICENSE).
