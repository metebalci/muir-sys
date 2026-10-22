"""tcp-check's part kill (README.md): a live TCP session's process killed.

A server's process killed with (send p :kill) while its client is connected
must not leave its connection behind: within BOUND s of the kill the client
sees EOF or RST, the process has left SI:ALL-PROCESSES, the connection has
left IP::TCP-CONNECTIONS, and IP::NETWORK-LOCK is free.  Two faults let it
leak: the TELNET server's abort close was not in an UNWIND-PROTECT, so a
kill's unwind skipped it; and a kill of a process that runs in another stack
group than its initial one (the debugger of a microcode error runs in the
error handler's) ran none of the initial stack group's UNWIND-PROTECTs.  The
cases, each a line of its own, run in --kill-cases' order:

  K1  a TELNET session in READ-LINE, killed from the control session
  K2  a TELNET session in the debugger after a microcode error and Y, in the
      error handler's stack group (checked before the kill), killed so
  K7  a TELNET session killed by a process of the band while it holds
      NETWORK-LOCK inside IP::TCP-SEND (advised: the session starts its
      killer and sleeps with the lock held; the case checks the kill landed
      under the lock)
  E1  the test echo service's server, killed so
  C2  a control: a TELNET session in the debugger, closed cleanly by its
      client (its FIN), no kill
  S1  a TELNET session in the debugger after Y types (send current-process
      :kill) itself: the form runs in the session's initial stack group while
      the process's STACK-GROUP slot, set only by the scheduler, still names
      the error handler's group; a kill that judges by that slot alone
      unwinds its own running group and halts the machine, and every later
      form gets no answer.  Last by default for that reason.

and after them a new TELNET session must answer a form (Z).  The part fails
when any case does.  Loaded by run (part_kill), which hands it its own
module, T2, for the band's and the control session's helpers.
"""

import socket
import threading
import time

BOUND = 15.0
CASES = ('K1', 'K2', 'K7', 'E1', 'C2', 'S1')
READ_LINE = '(progn (read-line) (list :got (read-line)))'


class Raw:
    """A session from a socket bound to the run's tap; a reader thread records
    what arrives and how the connection ended (EOF, RST or an error), and at
    the band's EOF closes our side, as a TELNET client does."""

    def __init__(self, band, log, name, port, banner='Telnet server here'):
        self.name, self.log, self.text = name, log, ''
        self.end = None
        self.s = band.connect(port)
        self.s.settimeout(0.2)
        self.port = self.s.getsockname()[1]
        self.th = threading.Thread(target=self._reader, daemon=True)
        self.th.start()
        if banner:
            self.until(banner, 120)

    def _reader(self):
        while self.end is None:
            try:
                d = self.s.recv(65536)
            except socket.timeout:
                continue
            except ConnectionResetError:
                self.end = ('RST', time.monotonic())
                break
            except OSError as e:
                self.end = ('error %s' % e, time.monotonic())
                break
            if not d:
                self.end = ('EOF', time.monotonic())
                try:
                    self.s.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                break
            t = d.decode('latin-1')
            self.log.write(t)
            self.text = (self.text + t)[-100000:]

    def until(self, what, secs):
        start = len(self.text)
        end = time.monotonic() + secs
        while what.lower() not in self.text[max(0, start - len(what)):].lower():
            if time.monotonic() > end:
                raise PartError('%s: no %r in %d s' % (self.name, what, secs))
            if self.end:
                raise PartError('%s: %s before %r' % (self.name, self.end[0], what))
            time.sleep(0.05)

    def send(self, text, crlf=True):
        self.s.sendall(text.encode('latin-1') + (b'\r\n' if crlf else b''))

    def wait_end(self, since, secs):
        while self.end is None and time.monotonic() < since + secs:
            time.sleep(0.05)
        return self.end

    def close(self):
        try:
            self.s.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        self.wait_end(time.monotonic(), 5)
        self.s.close()


class PartError(Exception):
    """A case that could not be set up as it should: it fails, and says why."""


class Cases:
    def __init__(self, t2, band, control, log):
        self.t2, self.band, self.control, self.log = t2, band, control, log
        self.v = control.value
        self.v('(progn (defvar user::*kill-p* nil) (setq ip:*test-echo-service* t) t)')

    def session(self, name, port=23, login=True):
        r = Raw(self.band, self.log, name, port, banner='Telnet server here' if port == 23 else None)
        if login:
            r.send(self.t2.lc.LOGIN_SYS_HOST)
            time.sleep(3)
        return r

    def grab(self, port):
        """The process of the band's server for our connection from PORT, as *KILL-P*."""
        self.v('(setq user::*kill-p* (ip::tcb-server-process (ip::tcp-connection-from-port %d)))' % port)

    def in_initial_sg(self):
        return self.v('(eq (send user::*kill-p* :stack-group) (send user::*kill-p* :initial-stack-group))')

    def state(self, port):
        return self.v('(list (if (memq user::*kill-p* si:all-processes) :alive :gone)'
                      ' (let ((c (ip::tcp-connection-from-port %d))) (and c (ip::tcb-state c))))' % port)

    def judge(self, r, since, event):
        """Within BOUND of SINCE: the client saw EOF or RST, the process is gone, the
        connection left the table; and then the lock is free.  Returns (ok, why)."""
        end = r.wait_end(since, BOUND)
        seen = []
        while True:
            st = self.state(r.port)
            dt = time.monotonic() - since
            if not seen or seen[-1][1] != st:
                seen.append((round(dt, 1), st))
            if st == '(:GONE NIL)' or dt > BOUND:
                break
            time.sleep(0.5)
        gone = st == '(:GONE NIL)'
        lock = self.v('(let ((l ip::network-lock)) (if l (send l :name) :free))')
        saw = '%s after %.1f s' % (end[0], end[1] - since) if end else 'nothing in %.0f s' % BOUND
        ok = bool(end) and end[0] in ('EOF', 'RST') and end[1] - since <= BOUND and gone and lock == ':FREE'
        return ok, ('after %s: the client saw %s; process and connection %s (%.1f s); lock %s; states %s'
                    % (event, saw, 'gone' if gone else 'NOT gone', dt, lock, seen))

    def debugger(self, r, form="(car 'x)"):
        """The session into the debugger: FORM's error, then Y at its question."""
        r.send(form)
        r.until('(Y or N)', 60)
        time.sleep(1)
        r.send('Y', crlf=False)
        r.until('->', 30)
        time.sleep(4)

    def kill(self, name, r):
        t = time.monotonic()
        self.v('(progn (send user::*kill-p* :kill) t)')
        return self.judge(r, t, 'the kill')

    def K1(self, name):
        r = self.session(name)
        self.grab(r.port)
        r.send(READ_LINE)
        time.sleep(4)
        try:
            return self.kill(name, r)
        finally:
            r.close()

    def K2(self, name):
        r = self.session(name)
        self.grab(r.port)
        self.debugger(r)
        try:
            if self.in_initial_sg() != 'NIL':
                return False, 'not set up: the session is not in another stack group than its initial one'
            return self.kill(name, r)
        finally:
            r.close()

    def K7(self, name):
        r = self.session(name)
        self.grab(r.port)
        self.v('(progn (defvar user::*kill-armed* nil) (defvar user::*kill-at-lock* :unset)'
               ' (setq user::*kill-armed* nil user::*kill-at-lock* :unset)'
               ' (si:advise ip::tcp-send :before kill-hold nil'
               ' (when (and user::*kill-armed* (eq current-process user::*kill-p*) (eq ip::network-lock current-process))'
               ' (setq user::*kill-armed* nil)'
               ' (process-run-function "kill killer" (function (lambda (p) (process-sleep 120)'
               ' (setq user::*kill-at-lock* (eq ip::network-lock p)) (send p :kill))) current-process)'
               ' (process-sleep 600))) t)')
        try:
            self.v('(setq user::*kill-armed* t)')
            t = time.monotonic()
            r.send('(+ 1 2)')
            ok, why = self.judge(r, t, 'the form (the kill 2 s later)')
            at = self.v('user::*kill-at-lock*')
            if at != 'T':
                return False, 'not set up: the kill did not land with the lock held (%s); %s' % (at, why)
            return ok, why + '; killed with the lock held'
        finally:
            self.v('(progn (setq user::*kill-armed* nil) (si:unadvise ip::tcp-send :before kill-hold) t)')
            r.close()

    def E1(self, name):
        r = self.session(name, port=7, login=False)
        r.send('hello echo')
        r.until('hello echo', 20)
        self.grab(r.port)
        try:
            return self.kill(name, r)
        finally:
            r.close()

    def C2(self, name):
        r = self.session(name)
        self.grab(r.port)
        self.debugger(r)
        t = time.monotonic()
        r.s.shutdown(socket.SHUT_WR)
        try:
            return self.judge(r, t, 'our FIN')
        finally:
            r.s.close()

    def S1(self, name):
        r = self.session(name)
        self.grab(r.port)
        self.debugger(r)
        try:
            if self.in_initial_sg() != 'NIL':
                return False, 'not set up: the session is not in another stack group than its initial one'
            t = time.monotonic()
            r.send('(send current-process :kill)')
            return self.judge(r, t, 'the typed kill')
        finally:
            r.close()


NAMES = {'K1': 'K1-kill-in-read-line', 'K2': 'K2-kill-in-debugger', 'K7': 'K7-kill-holding-network-lock',
         'E1': 'E1-kill-echo-server', 'C2': 'C2-clean-close-in-debugger', 'S1': 'S1-self-kill-typed-at-debugger'}


def part_kill(band, control, opts, log, t2):
    if control.a.network != 'tcp':
        raise t2.PartFailed('kill wants the control session over TCP')
    cases = Cases(t2, band, control, log)
    failed, done = [], []
    for k in opts.kill_cases:
        name = NAMES[k]
        t0 = time.monotonic()
        try:
            ok, why = getattr(cases, k)(name)
        except (OSError, PartError, t2.PartFailed, t2.lc.RunFailed) as e:
            ok, why = False, str(e) or type(e).__name__
        print('%-6s %-5s %s: %s (%.1f s)' % ('kill', 'PASS' if ok else 'FAIL', name, why, time.monotonic() - t0),
              flush=True)
        done.append(k)
        if not ok:
            failed.append(k)
        # a control session that no longer answers ends the part: every later
        # case would wait for it
        try:
            control.value('(+ 1 2)')
        except (OSError, t2.PartFailed, t2.lc.RunFailed) as e:
            rest = [x for x in opts.kill_cases if x not in done]
            raise t2.PartFailed('%s failed; then the control session did not answer (%s); not run: %s'
                                % (', '.join(failed) or 'none', e, ', '.join(rest) or 'none'))
    try:
        t2.telnet_session(band, '(* 6 7)', '42', log)
        z = 'a new session answers'
    except (OSError, t2.PartFailed, t2.lc.RunFailed) as e:
        failed.append('Z')
        z = 'a new session: %s' % e
    if failed:
        raise t2.PartFailed('%s of %s failed; %s' % (', '.join(failed), ', '.join(done), z))
    return '%s passed; %s' % (', '.join(done), z)
