#!/usr/bin/env bash

sudo umount -R /var/tmp/algabuild/tmp/*/{dev,proc,sys}
sudo rm -rf /var/tmp/algabuild/tmp/*
suffix="$(date -u +%Y%m%d%H%M%S)"
sudo perl scripts/build.pl --spec stage1-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix
sudo cp /var/tmp/algabuild/stages/stage1-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage1-algaos-latest.tar.xz
sudo perl scripts/build.pl --spec stage2-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix
sudo cp /var/tmp/algabuild/stages/stage2-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage2-algaos-latest.tar.xz
sudo perl scripts/build.pl --spec stage3-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix
sudo cp /var/tmp/algabuild/stages/stage3-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage3-algaos-latest.tar.xz
sudo perl scripts/build.pl --spec iso-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix
sudo cp /var/tmp/algabuild/stages/iso-algaos-$suffix.iso /var/tmp/algabuild/stages/iso-algaos-latest.iso
