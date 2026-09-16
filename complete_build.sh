#!/usr/bin/env bash

echo Are you sure you want a complete build? This will conflict with concurrent active builds
sleep 10;
read;
sudo umount -R /var/tmp/algabuild/tmp/*/{dev,proc,sys}
sudo rm -rf /var/tmp/algabuild/tmp/*
suffix=$1
if [ -z $suffix ]; then
    suffix="$(date -u +%Y%m%d%H%M%S)"
fi
#echo generating stage1
#if [ ! -e "/var/tmp/algabuild/stages/stage1-algaos-$suffix.tar.xz" ]; then 
#    sleep 5;
#    sudo perl scripts/build.pl --spec stage1-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix -j8 --binpkg-dir /var/tmp/algabuild/stages/binpkg-algaos-latest/ || exit 1
#    sudo cp /var/tmp/algabuild/stages/stage1-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage1-algaos-latest.tar.xz
#fi
#echo generating stage2
#if [ ! -e "/var/tmp/algabuild/stages/stage2-algaos-$suffix.tar.xz" ]; then 
#    sleep 5;
#    sudo perl scripts/build.pl --spec stage2-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix -j8 --binpkg-dir /var/tmp/algabuild/stages/binpkg-algaos-latest/ || exit 1
#    sudo cp /var/tmp/algabuild/stages/stage2-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage2-algaos-latest.tar.xz
#fi
echo generating stage3
if [ ! -e "/var/tmp/algabuild/stages/stage3-algaos-$suffix.tar.xz" ]; then 
    sleep 5;
    sudo perl scripts/build.pl --spec stage3-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix -j8 --binpkg-dir /var/tmp/algabuild/stages/binpkg-algaos-latest/ || exit 1
    sudo cp /var/tmp/algabuild/stages/stage3-algaos-$suffix.tar.xz /var/tmp/algabuild/stages/stage3-algaos-latest.tar.xz
fi
echo generating iso
if [ ! -e "/var/tmp/algabuild/stages/iso-algaos-$suffix.iso" ]; then 
    sleep 5;
    sudo perl scripts/build.pl --spec iso-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix -j8 --binpkg-dir /var/tmp/algabuild/stages/binpkg-algaos-latest/ || exit 1
    sudo cp /var/tmp/algabuild/stages/iso-algaos-$suffix.iso /var/tmp/algabuild/stages/iso-algaos-latest.iso
fi
if [ ! -e "/var/tmp/algabuild/stages/binpkg-algaos-$suffix" ]; then 
    sleep 5;
    sudo perl scripts/build.pl --spec binpkg-algaos.spec --repo ../algaos-ebuild-tree/ --suffix $suffix -j8 --binpkg-dir /var/tmp/algabuild/stages/binpkg-algaos-latest/ || exit 1
    sudo rsync -a --mkpath --delete /var/tmp/algabuild/stages/binpkg-algaos-$suffix/ /var/tmp/algabuild/stages/binpkg-algaos-latest/
fi
echo completed generation
