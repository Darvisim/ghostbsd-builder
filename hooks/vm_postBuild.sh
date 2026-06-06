# Runs inside the installed GhostBSD system as soon as the builder can ssh in.
# GhostBSD is FreeBSD under the hood, so this mirrors the freebsd-builder tuning:
# speed up boot and make sure the headless services we rely on are enabled.

echo '=================== postBuild start ===='

# --- Pick a working GhostBSD pkg mirror (so the post-install pkg step works) ---
# The default repo (pkg.ghostbsd.org) is hosted on Storj and periodically returns
# HTTP 403 "Bandwidth limit exceeded", which breaks "pkg install". GhostBSD ships
# ready-made mirror templates in /usr/local/etc/pkg/repos/GhostBSD.conf.<region>.
# Probe the main repo first (keep using it while it is healthy) and fall back to
# the regional mirrors, activating the first one that actually serves its
# catalogue by copying its template to the active override path. To restore the
# default later, remove /usr/local/etc/pkg/repos/GhostBSD.conf.
_abi=$(pkg config ABI 2>/dev/null)
[ -n "$_abi" ] || _abi="FreeBSD:15:amd64"
_active=/usr/local/etc/pkg/repos/GhostBSD.conf
for _m in default fr za ca no; do
  _tmpl="/usr/local/etc/pkg/repos/GhostBSD.conf.$_m"
  [ -f "$_tmpl" ] || continue
  _url=$(grep -m1 'url:' "$_tmpl" | sed -e 's|.*"\(http[^"]*\)".*|\1|' -e "s|[$]{ABI}|$_abi|")
  if fetch -qo /dev/null -T 25 "$_url/meta.conf" 2>/dev/null; then
    if [ "$_m" = default ]; then
      rm -f "$_active"
      echo "postBuild: GhostBSD pkg main repo healthy; using default."
    else
      cp "$_tmpl" "$_active"
      echo "postBuild: GhostBSD pkg main repo down; switched to mirror '$_m' ($_url)."
    fi
    break
  fi
  echo "postBuild: pkg mirror '$_m' unreachable, trying next..."
done

# fusefs is needed by sshfs (fusefs-sshfs); load it now and at every boot.
kldload fusefs || true
sysrc -f /boot/loader.conf fusefs_load="YES" || echo 'fusefs_load="YES"' >>/boot/loader.conf

# Faster, quieter boot.
cat <<EOF >>/boot/loader.conf
autoboot_delay="0"
loader_logo="NO"
loader_menu_title="NO"
zfs_load="YES"
EOF

sysrc rc_parallel="YES"

# Services we depend on for a headless image.
sysrc zfs_enable="YES"
sysrc sshd_enable="YES"
sysrc cron_enable="YES"
sysrc syslogd_enable="YES"

# Time sync.
service ntpd enable 2>/dev/null || sysrc ntpd_enable="YES"
service ntpd start 2>/dev/null || true

# Keep the desktop's display manager off so the image boots to a text console
# with sshd (re-assert in case the live media set it elsewhere).
for dm in lightdm slim gdm sddm xdm; do
  sysrc ${dm}_enable="NO"
done

# Make sure networking comes up via DHCP on whatever the NIC is called.
sysrc ifconfig_DEFAULT="DHCP"

echo "postBuild done."
