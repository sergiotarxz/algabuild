#!/usr/bin/env perl

use v5.40.0;
use strict;
use warnings;

use Getopt::Long;
use File::Temp qw(tempdir);

my $help;
my $from_scratch;
my $repo;
my $jobs = 4;
my $output_dir;
my $tag;
my $suffix;
my $binpkg_dir;
my $precursor;
my $source_stage_suffix = 'latest';

Getopt::Long::Configure( "bundling", "no_ignore_case" );
GetOptions(
    'help|h'             => \$help,
    'from-scratch|S'     => \$from_scratch,
    'repo=s'             => \$repo,
    'jobs|j=s'           => \$jobs,
    'tag|t=s'            => \$tag,
    'suffix'             => \$suffix,
    'output-dir|O=s'     => \$output_dir,
    'binpkg-dir=s'       => \$binpkg_dir,
    'precursor-dir|P=s'  => \$precursor,
    'src-stage-suffix=s' => \$source_stage_suffix,
);

$suffix //= $tag;

if ($help) {
    show_help();
    exit 0;
}

if ( !defined $tag ) {
    say STDERR "--tag|-t is mandatory";
    show_help();
    exit 1;
}

if ( !defined $output_dir ) {
    say STDERR "--output-dir|-O is mandatory";
    show_help();
    exit 1;
}

if ( !defined $repo ) {
    say STDERR "--repo is mandatory";
    show_help();
    exit 1;
}

if ( !defined $precursor || !-d $precursor ) {
    say $precursor;
    die 'No precursor dir';
}

if ( $< != 0 ) {
    say STDERR "Now try as root";
    show_help();
    exit 1;
}

my $tmp_tarball = tempdir(
    'algaos-complete-build-XXXXXX',
    DIR     => '/var/tmp/algabuild/tmp/',
    CLEANUP => 1,
);

if ( system qw{perl scripts/export_ebuild_tree.pl --repo},
    $repo, qw/--tag/, $tag, '--output-dir', $tmp_tarball, '--suffix', $suffix )
{
    die 'Failed to generate tarball';
}

my $tarball_file = "$tmp_tarball/webrsync-$suffix.tar.bz2";

if ( !-e $tarball_file ) {
    die "No tarball found at $tarball_file.";
}

my $tmp_repo = tempdir(
    'algaos-complete-build-repo-XXXXXX',
    DIR     => '/var/tmp/algabuild/tmp/',
    CLEANUP => 1,
);

my $tmp_out = tempdir(
    'algaos-complete-build-repo-XXXXXX',
    DIR     => '/var/tmp/algabuild/tmp/',
    CLEANUP => 1,
);

if ( system qw{tar -C}, $tmp_repo, qw{-xf}, $tarball_file ) {
    die "Failed to uncompress $tarball_file into $tmp_repo";
}

if (
    system qw/rsync --mkpath -a -P  --include=stage*amd64-systemd*.tar.xz/,
    "--include=stage*$source_stage_suffix*.tar.xz",
    qw/--exclude=*/,
    "$precursor/",
    "$tmp_out/stages/"
  )
{
    die "Unable to copy stages";
}

my @common_build_options = (
    qw/--repo/,
    $tmp_repo,
    qw/--suffix/, $source_stage_suffix, qw/--jobs/,
    $jobs,
    (
        defined $binpkg_dir ? ( '--binpkg-dir' => $binpkg_dir )
        : ()
    ),
    (
        defined $source_stage_suffix
        ? ( '--src-stage-suffix' => $source_stage_suffix )
        : ()
    ),
    qw/--tmp-dir/,
    $tmp_out,
);

my $iso    = "$tmp_out/stages/iso-algaos-$source_stage_suffix.iso";
my $stage3 = "$tmp_out/stages/stage3-algaos-$source_stage_suffix.tar.xz";
my $binpkg = "$tmp_out/stages/binpkg-algaos-$source_stage_suffix";

my @commands = (
    [
        qw{perl scripts/build.pl --spec stage3-algaos.spec},
        @common_build_options
    ],
    [
        qw{perl scripts/build.pl --spec binpkg-algaos.spec},
        @common_build_options
    ],
    [
        qw{perl scripts/build.pl --spec stage3-algaos.spec --clean-binpkg},
        @common_build_options, '--binpkg-dir', $binpkg
    ],
    [
        qw{perl scripts/build.pl --spec iso-algaos.spec --clean-binpkg},
        @common_build_options, '--binpkg-dir', $binpkg
    ],
);

if ($from_scratch) {
    @commands = ( 
        [
            qw{perl scripts/build.pl --spec stage1-algaos.spec},
            @common_build_options
        ],
        [
            qw{perl scripts/build.pl --spec stage2-algaos.spec},
            @common_build_options
        ],
        @commands,
    );
}


for my $command (@commands) {
    if ( system @$command ) {
        die 'Failed: ', join ' ', map { "'$_'" } @$command;
    }
}

if ( system qw/rsync --mkpath -a -P/,
    $tarball_file, "$output_dir/webrsync-$suffix.tar.bz2" )
{
    die 'Tarball copy failed';
}
if ( system qw/rsync --mkpath -a -P/,
    $stage3, "$output_dir/stage3-algaos-$suffix.tar.xz" )
{
    die 'Stage copy failed';
}
if ( system qw/rsync --mkpath -a -P/,
    $iso, "$output_dir/iso-algaos-$suffix.iso" )
{
    die 'ISO copy failed';
}
if ( system qw/rsync --mkpath -a -P/,
    "$binpkg/", "$output_dir/binpkg-algaos-$suffix/" )
{
    die 'Binpkg copy failed';
}

sub show_help {
    say <<'EOF';
perl scripts/complete_build.pl <options>

Options:
    <--tag|-t <git ebuild tree tag>: Selects the git tag/commit/branch to build AlgaOS from.
    <--output-dir|-O>: Selects where to output the result.
    <--repo <repo_dir>> Selects the git repo to use as base.
    <--precursor-dir <dir>> Sets the source for precursor stages
    [--from-scratch|-S] Generates stage1 and stage2 too
    [--jobs|-j <number>] Sets the number of jobs
    [--binpkg-dir <dir>] Sets the source of binpkg for faster compiling
    [--help|-h] Shows this help
EOF
}
