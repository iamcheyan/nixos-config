"""Add startup timing to the Nix build snapshot, without editing upstream."""
from pathlib import Path


def replace_once(path, before, after):
    file = Path(path)
    text = file.read_text()
    if text.count(before) != 1:
        raise SystemExit(f"{path}: startup instrumentation anchor changed: {before!r}")
    file.write_text(text.replace(before, after, 1))


main = "cmd/inua-shell/main.go"
replace_once(main, 'func main() {', '''func main() {
    log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
    log.Printf("startup: main pid=%d preload=%q", os.Getpid(), os.Getenv("INUA_LAYERSHELL_PRELOAD"))''')
replace_once(main, 'log.SetFlags(log.Ltime | log.Lmicroseconds)',
             'log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)')
replace_once(main, '\tdesktop.ReapInherited()',
             '\tlog.Print("startup: config begin")\n\tdesktop.ReapInherited()')
replace_once(main, '\tos.Exit(ui.Run(',
             '\tlog.Print("startup: config and i18n complete")\n\tos.Exit(ui.Run(')

shell = "internal/ui/shell.go"
replace_once(shell, 'func Run(opts Options) int {',
             'func Run(opts Options) int {\n\tlog.Print("startup: ui.Run / preload begin")')
replace_once(shell, '\tsocketPath := ipc.SocketPath(opts.Instance)',
             '\tlog.Print("startup: preload complete")\n\tsocketPath := ipc.SocketPath(opts.Instance)')
replace_once(shell, '\tstatus := int(app.Run(1, os.Args[:1]))',
             '\tlog.Print("startup: GtkApplication.Run begin")\n\tstatus := int(app.Run(1, os.Args[:1]))')
replace_once(shell, 'func (s *shellUI) start() {',
             'func (s *shellUI) start() {\n\tstartupBegin := time.Now()\n\tlog.Print("startup: GTK activate begin")')
for call in ['loadStyles', 'loadWallpaper', 'syncBars', 'startNotify',
             'startAlarms', 'startUpdates', 'startSystem', 'startAssistant',
             'startClipboardCapture', 'applyHyprland', 'scanApps', 'restartClock']:
    before = f'\ts.{call}()\n'
    after = (f'\tlog.Print("startup: {call} begin")\n' + before +
             f'\tlog.Printf("startup: {call} complete elapsed=%s", time.Since(startupBegin))\n')
    file = Path(shell)
    text = file.read_text()
    prefix, body = text.split('func (s *shellUI) start() {', 1)
    startup, suffix = body.split('\nfunc (s *shellUI) bindHandlers()', 1)
    if startup.count(before) != 1:
        raise SystemExit(f"{shell}: start() instrumentation anchor changed: {before!r}")
    startup = startup.replace(before, after, 1)
    file.write_text(prefix + 'func (s *shellUI) start() {' + startup +
                    '\nfunc (s *shellUI) bindHandlers()' + suffix)
replace_once(shell, '\tlog.Printf("startup: restartClock complete elapsed=%s", time.Since(startupBegin))',
             '''\tlog.Printf("startup: restartClock complete elapsed=%s", time.Since(startupBegin))
    gtkx.Post(func() {
        log.Printf("startup: main-loop idle after activate elapsed=%s (not a presentation timestamp)", time.Since(startupBegin))
    })''')
