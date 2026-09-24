#!/usr/bin/env perl
use strict;
use warnings;
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

my ($path) = @ARGV;
die "usage: $0 WORLD_LEVEL_DAT\n" unless defined $path;

my $data = '';
gunzip $path => \$data or die "cannot read $path: $GunzipError\n";

sub remove_string_from_list {
  my ($data_ref, $list_name, $target) = @_;
  my $header = pack('Cn a*C', 9, length($list_name), $list_name, 8);
  my $list_start = index($$data_ref, $header);
  die "missing NBT list $list_name\n" if $list_start < 0;

  my $count_offset = $list_start + length($header);
  my $count = unpack('N', substr($$data_ref, $count_offset, 4));
  my $cursor = $count_offset + 4;
  my ($match_start, $match_length, $matches) = (-1, 0, 0);

  for (1 .. $count) {
    die "truncated NBT list $list_name\n" if $cursor + 2 > length($$data_ref);
    my $length = unpack('n', substr($$data_ref, $cursor, 2));
    my $value_start = $cursor + 2;
    die "truncated NBT list $list_name\n" if $value_start + $length > length($$data_ref);
    my $value = substr($$data_ref, $value_start, $length);
    if ($value eq $target) {
      ($match_start, $match_length) = ($cursor, 2 + $length);
      ++$matches;
    }
    $cursor = $value_start + $length;
  }

  die "duplicate $target entries in $list_name\n" if $matches > 1;
  return 0 unless $matches;
  substr($$data_ref, $count_offset, 4, pack('N', $count - 1));
  substr($$data_ref, $match_start, $match_length, '');
  return 1;
}

my $feature_changed = remove_string_from_list(\$data, 'enabled_features', 'minecraft:trade_rebalance');
my $datapack_changed = remove_string_from_list(\$data, 'Enabled', 'trade_rebalance');
die "trade_rebalance remains enabled\n"
  if $data =~ /minecraft:trade_rebalance|(?<!minecraft:)trade_rebalance/;

gzip \$data => $path or die "cannot write $path: $GzipError\n";
printf "trade_rebalance feature=%s datapack=%s\n", $feature_changed ? 'removed' : 'absent', $datapack_changed ? 'removed' : 'absent';
