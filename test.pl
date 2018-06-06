#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;
use autodie;

sub usage {
  die "Usage: $0 host service from_ts to_ts\n";
}

my $host = $ARGV[0] or usage;
my $service = $ARGV[1] or usage;
my $from_ts = $ARGV[2] or usage;
my $to_ts = $ARGV[3] or usage;

my $last_event_state = 'UNDETERMINED';
my $last_event_ts = $from_ts;
my $in_downtime = 0;

my $avail = {
  all => 0,
  undetermined => 0,
  ok => 0,
  warning => 0,
  warning_scheduled => 0,
  warning_unscheduled => 0,
  unknown => 0,
  unknown_scheduled => 0,
  unknown_unscheduled => 0,
  critical => 0,
  critical_scheduled => 0,
  critical_unscheduled => 0,
};

sub host_state {
  my ($content, undef, $ts) = @_;

  my $state = {};
  ($state->{ host }, $state->{ state }, $state->{ state_type }, undef, $state->{ output }) = split /;/, $content, 5;
}
sub service_state { 
  my ($content, undef, $ts) = @_;

  return if ($ts <= $from_ts);
  return if ($ts > $to_ts);

  my $state = {};
  ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ state_type }, undef, $state->{ output }) = split /;/, $content, 6;

  # Only process if we're scanning for this host and service
  return unless (($state->{ host } eq $host) and ($state->{ service } eq $service));

  return if ($state->{ state_type } ne 'HARD');
  
  my $delta_t = $ts - $last_event_ts;
  add_to_availability($delta_t);

  $last_event_state = $state->{ state };
  $last_event_ts = $ts;
}

sub add_to_availability {
  my $duration = shift;

  $avail->{ all } += $duration;

  my $suffix = $avail->{ in_downtime } ? 'scheduled' : 'unscheduled';

  if ($last_event_state eq 'WARNING') {
    $avail->{ warning } += $duration;
    $avail->{ "warning_$suffix" } += $duration; 
  } elsif($last_event_state eq 'UNKNOWN') {
    $avail->{ unknown } += $duration;
    $avail->{ "unknown_$suffix" } += $duration;
  } elsif ($last_event_state eq 'CRITICAL') {
    $avail->{ critical } += $duration;
    $avail->{ "critical_$suffix" } += $duration;
  } elsif ($last_event_state eq 'OK') {
    $avail->{ ok } += $duration;
  } elsif ($last_event_state eq 'UNDETERMINED') {
    $avail->{ undetermined } += $duration;
  } else {
    die "ERROR: Unknown event state: $last_event_state";
  }
}

sub host_downtime { 
  my ($content, undef, $ts) = @_;

  return if ($ts <= $from_ts);
  return if ($ts > $to_ts);

  my $state = {};
  ($state->{ host }, $state->{ state }, $state->{ output }) = split /;/, $content, 3;

  # Only process if we're scanning for this host
  return unless ($state->{ host } eq $host);

  # add the time till the downtime event to the availability
  my $delta_t = $ts - $last_event_ts;
  add_to_availability($delta_t);
  $last_event_ts = $ts;

  if ($state->{ state } eq 'STOPPED') {
    $in_downtime = 0;
  } elsif ($state->{ state } eq 'CANCELLED') {
    $in_downtime = 0;
  } elsif ($state->{ state } eq 'STARTED') {
    $in_downtime = 1;
  } else {
    die "Unknown state $state->{ state }";
  }
}
sub service_downtime { 
  my ($content, undef, $ts) = @_;

  return if ($ts <= $from_ts);
  return if ($ts > $to_ts);

  my $state = {};
  ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ output }) = split /;/, $content, 4;

  # Only process if we're scanning for this host and service
  return unless (($state->{ host } eq $host) and ($state->{ service } eq $service));

  # add the time till the downtime event to the availability
  my $delta_t = $ts - $last_event_ts;
  add_to_availability($delta_t);
  $last_event_ts = $ts;

  if ($state->{ state } eq 'STOPPED') {
    $in_downtime = 0;
  } elsif ($state->{ state } eq 'CANCELLED') {
    $in_downtime = 0;
  } elsif ($state->{ state } eq 'STARTED') {
    $in_downtime = 1;
  } else {
    die "Unknown state $state->{ state }";
  }
}

sub end_file {
  my ($ts) = @_;

  my $delta_t = $ts - $last_event_ts;
  add_to_availability($delta_t);
  $last_event_ts = $ts;
}

sub no_type {
  my $content = shift;
  return if ($content =~ m/^Auto-save of retention data completed successfully\.$/);
  return if ($content =~ m/^Caught SIGHUP, restarting\.\.\.$/);
  return if ($content =~ m/^Event broker module .* (?:de)?initialized successfully\.$/);
  return if ($content =~ m/^Nagios \d\.\d\.\d starting/);
  return if ($content =~ m/^Local time is /);
  return if ($content =~ m/^Caught SIGTERM, shutting down\.\.\.$/);
  return if ($content =~ m/^Successfully shutdown\.\.\./);
  return if ($content =~ m/^Finished daemonizing\.\.\./);
  return if ($content =~ m/^Max concurrent service checks/);

  die "Unrecognized log content '$content'";
}

my $handlers = {
  'LOG ROTATION' => sub { },
  'LOG VERSION' => sub { },

  'HOST ALERT' => \&host_state,
  'CURRENT HOST STATE' => \&host_state,

  'SERVICE ALERT' => \&service_state,
  'CURRENT SERVICE STATE' => \&service_state,

  'HOST DOWNTIME ALERT' => \&host_downtime,
  'SERVICE DOWNTIME ALERT' => \&service_downtime,

  'SERVICE NOTIFICATION' => sub { },
  'SERVICE FLAPPING ALERT' => sub { },
  'EXTERNAL COMMAND' => sub { },
  'API LOG' => sub { },
  'SERVICE EVENT HANDLER' => sub { },
  'HOST NOTIFICATION' => sub { },
  'HOST FLAPPING ALERT' => sub { },
  'Warning' => sub {},
  'altinity_distributed_commands' => sub { },
  'altinity_set_initial_state' => sub { },
  'ndomod' => sub { },
  'opsview_distributed_notifications' => sub { },
  'opsview_notificationprofiles' => sub { },
  'no_type' => \&no_type,
};

my $log = *STDIN;
#open my $log, '<', 'logs/nagios-04-30-2018-00.log';
#open my $log, '<', 'logs/nagios-05-01-2018-00.log';
while (my $line = <$log>) {
  chomp $line;
  if (my ($ts, $type, $content) = ($line =~ m/\[(\d+)\] ([A-Za-z_ ]+?): (.*)/)) {
    #say $ts, $type, $content;
    my $handler = $handlers->{ $type };
    die "No handler for $type in\n$line" if (not defined $handler);
    $handlers->{ $type }->($content, $type, $ts);
  } elsif (my ($ts_2, $content_2) = ($line =~ m/\[(\d+)\] (.*)/)) {
    $handlers->{ no_type }->($content_2, $ts_2);
  } else {
    die "Unrecognized log line '$line'";  
  }
}
end_file($to_ts);

use Data::Dumper;
print Dumper($avail);

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
