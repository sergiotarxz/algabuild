prefix: "stage2-algaos-"
source: "stage1-algaos-latest.tar.xz"
profile: "algaos:default/linux/amd64/23.0/algaos/desktop/default/systemd"
break_circular:
    uses: "-sysprof -avif"
    package_use: |
        dev-python/pillow -truetype
repo_name: 'algaos'
repos_conf: |
    [DEFAULT]
    main-repo = algaos

    [algaos]
    location = /var/db/repos/algaos
    sync-type = git
    sync-uri = https://github.com/sergiotarxz/algaos-ebuild-tree.git
    auto-sync = yes
