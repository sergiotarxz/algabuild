#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw(GetOptions);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my ($repo, $tag, $output_dir, $suffix);
my $help;

GetOptions(
    'repo=s'       => \$repo,
    'tag=s'        => \$tag,
    'output-dir=s' => \$output_dir,
    'suffix=s'     => \$suffix,
    'help|h'       => \$help,
) or usage(1);

usage(0) if $help;
usage(1) unless defined $repo && defined $tag && defined $suffix;

$output_dir //= '.';

sub usage {
    my ($exit) = @_;

    print <<"EOF";
Usage: $0 --repo PATH --tag TAG --suffix SUFFIX [--output-dir DIR]

Options:
    --repo PATH       Git repository
    --tag TAG         Git tag
    --suffix SUFFIX   Snapshot filename suffix
    --output-dir DIR  Output directory (default: .)
    --help, -h        Show this help

Output:
    webrsync-SUFFIX.tar.bz2

EOF

    exit $exit;
}

sub run {
    my (@cmd) = @_;

    print '+ ', join(' ', @cmd), "\n";

    system(@cmd);

    die "command failed: $?\n" if $? == -1;
    die "command failed: signal " . ($? & 127) . "\n" if $? & 127;
    die "command failed: exit " . ($? >> 8) . "\n" if $? >> 8;
}

die "Repository does not exist: $repo\n"
    unless -d $repo;

make_path($output_dir)
    unless -d $output_dir;

my $tmp = tempdir(
    'webrsync-XXXXXX',
    TMPDIR  => 1,
    CLEANUP => 1,
);

my $tree = "$tmp/tree";
my $archive = "$tmp/tree.tar";

make_path($tree);

run(
    'git',
    '-C', $repo,
    'archive',
    '--format=tar',
    '--output', $archive,
    $tag,
);

run(
    'tar',
    '-xf', $archive,
    '-C', $tree,
);

my $timestamp = "$tree/metadata/timestamp.x";

make_path("$tree/metadata");

open my $fh, '>', $timestamp
    or die "$timestamp: $!\n";

print {$fh} time, "\n"
    or die "$timestamp: $!\n";

close $fh
    or die "$timestamp: $!\n";

my $output = "$output_dir/webrsync-$suffix.tar.bz2";

if (system qw{rsync -P --delete -a}, 'rsync://rsync.gentoo.org/gentoo-portage/metadata/glsa/', "$tree/metadata/glsa/") {
    die 'Unable to append security advisories (glsa)';
}

run(
    'tar',
    '-C', $tree,
    '--sort=name',
    '-cjf', $output,
    '.',
);

print "Created $output\n";
