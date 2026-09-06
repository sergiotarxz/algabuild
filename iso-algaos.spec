prefix: "iso-algaos-"
source: "stage3-algaos-latest.tar.xz"
profile: "algaos:default/linux/amd64/23.0/algaos/desktop/default/systemd/cdrom"
repo_name: 'algaos'
image_type: 'iso'
commands:
    - systemd-machine-id-setup
    - systemctl preset-all
    - systemctl enable gdm
    - systemctl enable NetworkManager
    - systemctl enable cronie
    - systemctl enable sshd
    - useradd -m user -s /bin/bash || exit 0
    - passwd -d user
    - gpasswd -a user plugdev
    - mkdir -pv /etc/sudoers.d
    - |
        cat <<'EOF'>/etc/sudoers.d/livecd
        user ALL=(ALL) NOPASSWD: ALL
        EOF
    - |
        cat <<'EOF'>/etc/gdm/custom.conf
        [daemon]
        AutomaticLoginEnable=true
        AutomaticLogin=user
        EOF
    - emerge plymouth-theme-colorful-loop
    - |
        plymouth-set-default-theme -R colorful_loop
    - |
        export KVER=$(find /lib/modules -mindepth 1 -maxdepth 1 -type d \
            -printf '%f\n' | sort -V | tail -n1)

        dracut --force \
            --kver "$KVER" \
            --no-hostonly \
            --stdlog 6 \
            --force \
            --add "dmsquash-live" \
            "/boot/initramfs-${KVER}.img"
#transfer:
#    - [1000, 1000, '../../.ssh/', '/home/user/.ssh/']
