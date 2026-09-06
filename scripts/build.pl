#!/usr/bin/env perl

use v5.40.0;
use strict;
use warnings;

use File::Basename qw/dirname/;
use File::pushd    qw/pushd/;
use Getopt::Long;
use YAML::XS;

my $help;
my $ebuild_tree;
my $spec;
my $suffix;
my $jobs = 4;
my $skip_initial_setup;

Getopt::Long::Configure( "bundling", "no_ignore_case" );
GetOptions(
    'repo|r=s'           => \$ebuild_tree,
    'spec|s=s'           => \$spec,
    'suffix|S=s'         => \$suffix,
    'jobs|j=s'           => \$jobs,
    'skip-initial-setup' => \$skip_initial_setup,
    'help'               => \$help
);

if ( !$help ) {
    $spec        or warn 'no spec file';
    $ebuild_tree or warn 'no ebuild tree';
}
if ( $help || !$spec || !$ebuild_tree ) {
    print <<'EOF';
perl scripts/build.pl [-h|--help] <-r|--repo> <ebuild tree> <-s|--spec> <spec file>

Options:

<-r|--repo <ebuild tree>>: Select the ebuild repository
<-s|--spec <spec file>>: Select spec file
[-S|--suffix <generated stage suffix>]: Select spec file
[-j|--jobs <number of jobs>]: Select number of jobs
[--skip-initial-setup]: Avoids creating the ebuild tree and uncompressing the source stage for faster debugging
[-h|--help]: Show this help.
EOF
    exit 0;
}

$suffix = $suffix // `date -u +%Y%m%dT%H%M%SZ`;
chomp $suffix;

die 'Now try it as root' if $< != 0;

my $algabuild_dir = '/var/tmp/algabuild';
my $tmp           = "$algabuild_dir/tmp";
system mkdir => -pv => $tmp;
my $stage_dir = "$algabuild_dir/stages";
system mkdir => -pv => $stage_dir;

die "$spec does not exist" if !-e $spec;

my $yaml = YAML::XS::LoadFile($spec);

my $repo_name    = $yaml->{repo_name} // 'gentoo';
my $prefix       = $yaml->{prefix} or die 'No stage prefix in yaml';
my $stage_name   = $prefix . $suffix;
my $source       = $yaml->{source}  or die 'No source stage in yaml';
my $profile      = $yaml->{profile} or die 'No profile in yaml';
my $rebuild_all  = $yaml->{rebuild_all};
my $source_stage = "$stage_dir/$source";

die "$source_stage does not exist" if !-e $source_stage;

my %image_types = (
    iso => sub {
        say 'Creating iso';
        create_iso();
    },
    stage => sub {
        say 'Creating stage';
        create_stage();
    },
    binpkg => sub {
        say 'Creating binpkgs for the whole system';
        create_binpkgs();
    },
);

my $image_type = $yaml->{image_type} // 'stage';

my $callback = $image_types{$image_type};

if ( !defined $callback ) {
    die "$image_type image_type not recognized";
}

$callback->();

sub generate_root_tmp {
    my $tmp_new_stage = shift;
    if ( !$skip_initial_setup ) {
        system qw{tar -C}, $tmp_new_stage, '-xvpf', $source_stage,
          qw{--numeric-owner --xattrs-include=*.*};
        system qw{rsync --exclude=.git -a -P}, "$ebuild_tree/",
          "$tmp_new_stage/var/db/repos/$repo_name/";
    }
    system qw{cp -Lv /etc/resolv.conf}, "$tmp_new_stage/etc";
    if ( $yaml->{repos_conf} ) {
        open my $fh, '>', "$tmp_new_stage/usr/share/portage/config/repos.conf"
          or die 'Unable to write repos.conf';
        print $fh $yaml->{repos_conf};
        close $fh;
    }
}

sub prepare_root {
    my $commands = $yaml->{commands};
    if ( defined $commands && ref $commands ne 'ARRAY' ) {
        die "List of commands is not an array";
    }
    local $ENV{MAKEOPTS} = "-j$jobs";
    my $link_profile = `readlink /etc/portage/make.profile`;
    chomp $link_profile;
    if ( $link_profile && $link_profile =~ s/gentoo/$repo_name/g ) {
        if ( system rm => -v => '/etc/portage/make.profile' ) {
            die 'Unable to delete profile';
        }
        if ( system ln => -sv => $link_profile => '/etc/portage/make.profile' )
        {
            die "Unable to link profile to $link_profile";
        }
        if ( system qw{emerge -uUDN @world @system} ) {
            die 'Unable to finish previous profile';
        }
        if ( system qw{emerge @preserved-rebuild} ) {
            die 'Unable to finish previous profile';
        }
        my $profile_for_grep = $profile =~ s/^[^\/]*://r;
        if ( !system qw{grep -R clang},
            "/var/db/repos/$repo_name/profiles/$profile_for_grep" )
        {
            install_clang();
        }
    }
    if ( system qw{eselect profile set}, $profile ) {
        die "Could not set profile $profile";
    }
    my $is_binpkg = $yaml->{image_type} eq 'binpkg';
    if ($rebuild_all || $is_binpkg) {
        die "Could not build the system"
          if system( qw{emerge -e --with-bdeps=y @world @system},
            $is_binpkg ? ('--buildpkg') : () );
    }
    else {
        if ( $yaml->{break_circular} ) {
            local $ENV{USE} = $yaml->{break_circular}{uses};
            my $tmp_use_file =
              '/etc/portage/package.use/999-temporal-cycle-breaker';
            open my $fh, '>', $tmp_use_file;
            say $fh $yaml->{break_circular}{package_use};
            $fh->flush;
            install_clang_if_needed();
            die "Could not build the system"
              if system qw{emerge --noreplace --with-bdeps=y @world @system};
            die "Could not build the system"
              if system qw{emerge -uUDN --with-bdeps=y @world @system};

            if ( system rm => $tmp_use_file ) {
                die 'Failed to delete tmp cycle breaker package.use file';
            }
        }
        install_clang_if_needed();
        die "Could not build the system"
          if system qw{emerge --noreplace --with-bdeps=y @world @system};
        die "Could not build the system"
          if system qw{emerge -uUDN --with-bdeps=y @world @system};
    }
    die "Could not set the default editor"
      if system qw{emerge --noreplace vim};
    die "Could not set the default editor"
      if system qw{eselect editor set vim};
    system qw{emerge --depclean --with-bdeps=y};
    my @commands = @{ $commands // [] };
    for my $command (@commands) {
        say "Running command $command";
        if ( system $command ) {
            die "($command) failed with exit code not 0";
        }
    }
    system qw{rm /etc/resolv.conf};
    system qw{touch /success};
}

sub create_binpkgs {
    my $tmp_new_stage = "$tmp/$stage_name";
    my $rootfs_path   = "$tmp_new_stage-root";
    system qw{mkdir -pv}, $rootfs_path;
    generate_root_tmp($rootfs_path);
    mount_eval(
        $rootfs_path,
        sub {
            prepare_root();
        }
    );
    finish_root($rootfs_path);
    if (system qw{rsync --mkpath -a -P}, "$rootfs_path/var/cache/binpkgs/", "$stage_dir/$stage_name/") {
        die 'Copying binpkgs failed';
    }
}

sub create_iso {
    my $tmp_new_stage = "$tmp/$stage_name";
    my $rootfs_path   = "$tmp_new_stage-rootfs";
    system qw{mkdir -pv}, $rootfs_path;
    my $contents_path = "$tmp_new_stage-contents";
    system qw{mkdir -pv}, $contents_path;
    generate_root_tmp($rootfs_path);
    mount_eval(
        $rootfs_path,
        sub {
            prepare_root();
        }
    );
    finish_root($rootfs_path);
    system qw{rm}, "$contents_path/rootfs.squashfs";
    system qw{cp -v}, $source_stage, $rootfs_path;
    if (system qw{mksquashfs}, $rootfs_path, "$contents_path/rootfs.squashfs") {
        die "Couldn't generate squashfs";
    }
    my $grub_dir = "$contents_path/boot/grub";
    system qw{mkdir -pv}, $grub_dir;
    open my $fh, '>', "$grub_dir/grub.cfg";
    my ($kver) = reverse glob("$rootfs_path/boot/kernel-*");
    die "No kernel found in $rootfs_path/boot\n" unless $kver;

    $kver =~ s{.*/kernel-}{};
    say $fh <<"EOF";
set timeout=5
set default=0

menuentry "AlgaOS" {
    linux /boot/kernel-$kver root=live:LABEL=ALGAOS rd.live.dir=/ rd.live.squashimg=rootfs.squashfs rd.live.overlay.overlayfs=1 rd.live.debug=1 rd.systemd.show_status=1 rd.systemd.log_level=debug quiet splash
    initrd /boot/initramfs-$kver.img
};
EOF
    if (system "cp -v $rootfs_path/boot/kernel* $contents_path/boot/") {
        die 'Unable to copy kernel';
    }
    if (system "cp -v $rootfs_path/boot/initramfs* $contents_path/boot/") {
        die 'Unable to copy initramfs';
    }
    if (system qw{grub-mkrescue -iso-level 3 -volid ALGAOS -o}, "$stage_dir/$stage_name.iso", "$contents_path") {
        die 'Unable to create ISO with grub-mkrescue"';
    }
}


sub create_stage {
    my $tmp_new_stage = "$tmp/$stage_name";
    system mkdir => -pv => $tmp_new_stage;

    generate_root_tmp($tmp_new_stage);
    mount_eval(
        $tmp_new_stage,
        sub {
            prepare_root();
        }
    );
    finish_root($tmp_new_stage);
    system qw{tar -C}, $tmp_new_stage, qw{-cvJf},
      "$stage_dir/$stage_name.tar.xz",
      qw{--numeric-owner --xattrs-include=*.* .};
}

sub finish_root {
    my $tmp_new_stage = shift;
    die "System not marked successful" if !-e "$tmp_new_stage/success";
    for my $transfer (@{$yaml->{transfer} // []}) {
        my ($user, $group, $source, $dest) = @$transfer;
        if (system qw{rsync -P -a}, "--chown=$user:$group", qw{--mkpath}, $source, "$tmp_new_stage/$dest") {
            die "Transfer failed $source -> $dest";
        }
    }
    system rm => "$tmp_new_stage/success";
    system "rm -rf $tmp_new_stage/var/cache/distfiles/*";
    system "rm -rf $tmp_new_stage/var/db/repos/*";
}

sub install_clang_if_needed {
    my $new_packages = `emerge -pv --noreplace --with-bdeps=y \@world`;
    if ( $new_packages =~ /spidermonkey|firefox/ ) {
        install_clang();
    }
}

sub install_clang {
    if ( system qw{emerge --noreplace llvm-core/clang} ) {
        die "Failed to install clang";
    }
}

sub mount_eval {
    my $tmp_new_stage = shift;
    my $callback      = shift;
    my $chdir         = pushd $tmp_new_stage;
    local $SIG{INT} = 'ignore';
    system qw{mount -t proc proc proc};
    system qw{mount -t sysfs sysfs sys};
    system qw{mount --rbind /dev dev};
    system qw{mount --make-rslave dev};
    system qw{mount --make-rslave sys};
    system qw{mount --make-rslave proc};
    my $pid = fork;

    if ( !$pid ) {
        chroot $tmp_new_stage;
        chdir '/';
        eval { $callback->(); };
        if ($@) {
            warn "error: $@";
            exit 1;
        }
        exit 0;
    }
    waitpid $pid, 0;
    sleep 5;

    system 'umount -R dev sys proc';

    if ( $? == -1 ) {
        die "waitpid failed: $!";
    }

    if ( $? & 127 ) {
        die "child died from signal " . ( $? & 127 );
    }

    my $exit = $? >> 8;
    die "child exited with status $exit" if $exit != 0;
}
