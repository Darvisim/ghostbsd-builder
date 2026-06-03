# Unattended install driver for GhostBSD.
#
# GhostBSD only ships a live GUI installer (gbi), which is a front-end for the
# scriptable pc-sysinstall backend. There is no downloadable VM disk image, so we
# boot the live ISO, reach a root shell on the fully-booted live system, and run
# pc-sysinstall directly with our own answer file (conf/pcinstall.cfg) -- exactly
# the command gbi itself runs: `sudo /usr/local/sbin/pc-sysinstall -c <cfg>`.
#
# This hook is sourced by build.sh (the ISO branch) with $vmsh, $osname,
# waitForText() and inputKeys() already defined, the VNC/OCR screen loop running,
# and a python http.server serving this repo at http://192.168.122.1:8000/ .
#
# IMPORTANT: the screen-driving timings and the live-console login below are the
# parts that need empirical tuning in CI (like every other builder here). They
# are written to be easy to adjust -- see README.md "Status".

set -x

# vbox.sh installs vncdotool on PATH; string()/enter() already use it.
_vnc() { vncdotool "$@"; }

############################################################################
# 1) Let the live ISO autoboot all the way to the desktop.
#    The GhostBSD loader autoboots on its own; we just wait for the live
#    system to finish coming up. MATE/XFCE live takes a while under QEMU.
############################################################################
echo "Waiting for the GhostBSD live system to boot..."
sleep 150

############################################################################
# 2) Switch from the graphical session (running on a high vt) to a text
#    console (ttyv1) so we can drive a shell deterministically with OCR.
############################################################################
echo "Switching to text console ttyv1 (Ctrl+Alt+F2)..."
_vnc key ctrl-alt-f2
sleep 3
_vnc key ctrl-alt-f2

# Wait for the getty login prompt on the text console. OCR renders the live
# media's "login:" consistently as "logi", so match that.
waitForText "logi" 300

############################################################################
# 3) Log in. On the GhostBSD live media root logs in on the console with no
#    password. If that ever changes, this is the spot to add a password.
############################################################################
$vmsh string "root"
$vmsh enter
sleep 5
# Harmless extra Enter in case a (empty) password prompt is shown.
$vmsh enter
sleep 5

# Give the shell a moment to settle after login. We avoid OCR-matching the
# "root@livecd" prompt here because OCR mangles the "@" (reads it as "rootel
# ivec"); login is near-instant once the "logi" prompt is reached, so a short
# fixed wait is more reliable.
sleep 15

############################################################################
# 4) Fetch our answer file from the builder's HTTP server and run
#    pc-sysinstall, then power the VM off so build.sh proceeds. We go through
#    sudo so the same line works whether the live login is root or the live
#    user (gbi relies on passwordless sudo on the live media).
############################################################################
$vmsh string "sudo fetch -o /tmp/pcinstall.cfg http://192.168.122.1:8000/conf/pcinstall.cfg"
$vmsh enter
sleep 5
# Show the config in the build log for debugging.
$vmsh string "cat /tmp/pcinstall.cfg"
$vmsh enter
sleep 3

$vmsh string "sudo /usr/local/sbin/pc-sysinstall -c /tmp/pcinstall.cfg"
$vmsh enter

# Give pc-sysinstall time to partition, create the pool and clone the live
# filesystem to disk. build.sh waits for the VM to power off after this hook
# returns, so block here until the install is plausibly done.
echo "Running pc-sysinstall; waiting for it to finish..."
# pc-sysinstall prints "Installation finished!" on success (OCR sees the "!"
# as "?"), so match the OCR-robust substring "finished".
waitForText "finished" 1200 || true

sleep 10
$vmsh string "sudo shutdown -p now"
$vmsh enter
