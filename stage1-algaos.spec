prefix: "stage1-algaos-"
source: "stage3-amd64-systemd-latest.tar.xz"
profile: "algaos:default/linux/amd64/23.0/algaos/systemd"
repo_name: 'algaos'
rebuild_all: 1
repos_conf: |
    [DEFAULT]
    main-repo = algaos

    [algaos]
    location = /var/db/repos/algaos
    sync-type = git
    sync-uri = https://github.com/sergiotarxz/algaos-ebuild-tree.git
    auto-sync = yes
