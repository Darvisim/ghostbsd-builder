# Authorize the builder's SSH key on the installed VM (GhostBSD override).
#
# This hook EXISTS to override base-builder/build.py's default
# _enable_ssh_root_branch path, which runs:
#
#     sshpass ... ssh -p $sshport -tt ... root@127.0.0.1 TERM=xterm <enablessh.local
#
# That trick works on most BSDs because the remote shell stays interactive
# under -tt and reads stdin after the "TERM=xterm" command completes. On
# GhostBSD (root's login shell /bin/sh), it does not: the shell exits as
# soon as the TERM=xterm assignment completes, the pty drains, and the
# piped enablessh.local is never executed. The builder's key never lands
# in /root/.ssh/authorized_keys and every later key-based ssh fails with
# "Too many authentication failures" (exit 255).
#
# Pipe the script to an explicit `sh` instead. Connect via the slirp
# hostfwd port on 127.0.0.1 (the guest's 192.168.122.x is not
# host-reachable under user-mode networking).
#
# Host-side hook: run by base-builder/build.py via exec() in this module's
# globals, so subprocess / time / log / env / read_state are bare names.

osname = env("VM_OS_NAME")
sshport = read_state(osname, "sshport", "").strip()
log("enablessh: piping enablessh.local to sh over hostfwd 127.0.0.1:%s" % sshport)

with open("enablessh.local", "rb") as inp:
    subprocess.run(
        ["sshpass", "-p", env("VM_ROOT_PASSWORD"), "ssh",
         "-p", sshport,
         "-o", "StrictHostKeyChecking=no",
         "-o", "UserKnownHostsFile=/dev/null",
         "-o", "PreferredAuthentications=password",
         "-o", "PubkeyAuthentication=no",
         "root@127.0.0.1", "sh"],
        stdin=inp)

# Give sshd a moment; build.py's own retry loop verifies key-based access next.
time.sleep(5)
