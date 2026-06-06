# Unattended install driver for GhostBSD.
#
# GhostBSD only ships a live GUI installer (gbi), which is a front-end for the
# scriptable pc-sysinstall backend. There is no downloadable VM disk image, so we
# boot the live ISO, reach a root shell on the live system via the text console,
# and run pc-sysinstall directly with our own answer file (conf/pcinstall.cfg) --
# exactly the command gbi itself runs:
#
#     sudo /usr/local/sbin/pc-sysinstall -c <cfg>
#
# Host-side hook: run by base-builder/build.py via exec() in this module's
# globals, so waitForText / string / enter / inputKeys / vncKey / sleep / log /
# env / subprocess are all available as bare names.
#
# IMPORTANT: the screen-driving timings and the live-console login below are
# the parts most likely to need empirical tuning in CI -- this is the place to
# tune them.

# Under raw QEMU + slirp the guest always reaches the build host at
# 192.168.122.1 (build.py pins `host=` in -netdev user). The old libvirt-era
# network probe is gone.
_cfg_url = "http://192.168.122.1:8000/conf/pcinstall.cfg"

# Trailing shell-comment pad. vncdotool occasionally drops the last few chars
# it types under load; appending a comment pad guarantees a tail-drop eats the
# pad rather than the real command or filename.
_pad = "          #zzzzzzzzzzzzzzzz"

############################################################################
# 1) Reach a text-console login prompt.
#
#    The GhostBSD live ISO copies itself into a swap-backed memdisk and
#    REROOTS before the login getty appears. On a slow/contended host that
#    copy can take the better part of an hour, so a single early Ctrl+Alt+F2
#    is lost across the reroot. Re-issue Ctrl+Alt+F2 on every poll via the
#    waitForText hook so the switch to ttyv1 is re-asserted until the getty
#    prompt actually appears -- regardless of how long the boot takes.
#    OCR renders the live media's "login:" consistently as "logi".
############################################################################
log("Waiting for the GhostBSD live system to boot and reach a login prompt...")
time.sleep(60)
vncKey("ctrl-alt-f2")
waitForText("logi", "400", hook=lambda: vncKey("ctrl-alt-f2"))

############################################################################
# 2) Log in. On the GhostBSD live media root logs in on the console with no
#    password. If that ever changes, this is the spot to add a password.
############################################################################
string("root")
enter()
time.sleep(5)
# Harmless extra Enter in case an (empty) password prompt is shown.
enter()
time.sleep(15)

############################################################################
# 3) Fetch our answer file from the build host and run pc-sysinstall, then
#    power the VM off so build.py proceeds. We go through sudo so the same
#    line works whether the live login is root or the live user (gbi relies
#    on passwordless sudo on the live media). The fetch is issued twice (it
#    is idempotent) to ride out a transient hiccup just after the live
#    network comes up.
############################################################################
string("sudo fetch -o /tmp/pcinstall.cfg %s%s" % (_cfg_url, _pad))
enter()
time.sleep(12)
string("sudo fetch -o /tmp/pcinstall.cfg %s%s" % (_cfg_url, _pad))
enter()
time.sleep(8)
# Show the config in the build log for debugging.
string("cat /tmp/pcinstall.cfg%s" % _pad)
enter()
time.sleep(3)

string("sudo /usr/local/sbin/pc-sysinstall -c /tmp/pcinstall.cfg%s" % _pad)
enter()

# Give pc-sysinstall time to partition, create the pool and clone the live
# filesystem to disk. build.py waits for the VM to power off after this hook
# returns, so block here until the install is plausibly done.
# pc-sysinstall prints "Installation finished!" on success (OCR sees the "!"
# as "?"), so match the OCR-robust substring "finished".
log("Running pc-sysinstall; waiting for it to finish...")
waitForText("finished", "1200")

time.sleep(10)
string("sudo shutdown -p now%s" % _pad)
enter()
