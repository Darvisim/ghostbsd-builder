# Runs inside the installed GhostBSD system as soon as the builder can ssh in.
# GhostBSD is FreeBSD under the hood, so this mirrors the freebsd-builder tuning:
# speed up boot and make sure the headless services we rely on are enabled.

echo '=================== postBuild start ===='

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
