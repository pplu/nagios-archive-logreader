#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;
use Monitoring::SLACalculator;
use DateTime;
use DateTime::Format::Human::Duration;

sub usage {
  die "Usage: $0 host service from_ts to_ts\n";
}

my $host = $ARGV[0] or usage;
my $service = $ARGV[1] or usage;
my $from_ts = $ARGV[2] or usage;
my $to_ts = $ARGV[3] or usage;

my $sla = Monitoring::SLACalculator->new(
  from_ts => $from_ts,
  to_ts => $to_ts,
  host => $host,
  service => $service,
);
$sla->process;

my $avail = $sla->avail;

my $dur = DateTime::Format::Human::Duration->new();
printf "For Host $host Service $service\n";
printf "From %s to %s\n", DateTime->from_epoch(epoch => $from_ts)->iso8601,
                        DateTime->from_epoch(epoch => $to_ts)->iso8601;
printf "All %s\n", $dur->format_duration(DateTime::Duration->new(seconds => $avail->{ all }));
printf "OK       Total\t%03.2f\n", ($avail->{ ok }       / $avail->{ all }) * 100;
printf "Warning  Total\t%03.2f\n", ($avail->{ warning }  / $avail->{ all }) * 100;
printf "  Scheduled\t%03.2f\n",    ($avail->{ warning_scheduled }  / $avail->{ all }) * 100;
printf "  Unscheduled\t%03.2f\n",    ($avail->{ warning_unscheduled }  / $avail->{ all }) * 100;
printf "Unknown  Total\t%03.2f\n", ($avail->{ unknown }  / $avail->{ all }) * 100;
printf "  Scheduled\t%03.2f\n",    ($avail->{ unknown_scheduled }  / $avail->{ all }) * 100;
printf "  Unscheduled\t%03.2f\n",    ($avail->{ unknown_unscheduled }  / $avail->{ all }) * 100;
printf "Critical Total\t%03.2f\n", ($avail->{ critical } / $avail->{ all }) * 100;
printf "  Scheduled\t%03.2f\n",    ($avail->{ critical_scheduled }  / $avail->{ all }) * 100;
printf "  Unscheduled\t%03.2f\n",    ($avail->{ critical_unscheduled }  / $avail->{ all }) * 100;
printf "Undetermined\t%03.2f\n", ($avail->{ undetermined } / $avail->{ all }) * 100;
