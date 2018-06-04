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

my $avail = {
  first_event => undef,
  last_event => undef,
  in_downtime => 0,
  all => 0,
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
 
  my $state = {};
  ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ state_type }, undef, $state->{ output }) = split /;/, $content, 6;

  # Only process if we're scanning for this host and service
  return unless (($state->{ host } eq $host) and ($state->{ service } eq $service));

  return if ($state->{ state_type } ne 'HARD');

  if (not defined $avail->{ last_event }){
    $avail->{ last_event } = $ts;
    $avail->{ first_event } = $ts;
  }

  my $delta_t = $ts - $avail->{ last_event };

  $avail->{ all } += $delta_t;
  $avail->{ ok } += $delta_t if ($state->{ state } eq 'OK');
  $avail->{ warning } += $delta_t if ($state->{ state } eq 'WARNING');
  $avail->{ unknown } += $delta_t if ($state->{ state } eq 'UNKNOWN');
  $avail->{ critical } += $delta_t if ($state->{ state } eq 'CRITICAL');

  $avail->{ last_event } = $ts;
}

sub host_downtime { 
  my ($content, undef, $ts) = @_;

  my $state = {};
  ($state->{ host }, $state->{ state }, $state->{ output }) = split /;/, $content, 3;
}
sub service_downtime { 
  my ($content, undef, $ts) = @_;

  my $state = {};
  ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ output }) = split /;/, $content, 4;
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

use Data::Dumper;
print Dumper($avail);

printf
printf "OK       Total\t%2.3f\n", ($avail->{ ok }       / $avail->{ all });
printf "Warning  Total\t%2.3f\n", ($avail->{ warning }  / $avail->{ all });
printf "Unknown  Total\t%2.3f\n", ($avail->{ unknown }  / $avail->{ all });
printf "Critical Total\t%2.3f\n", ($avail->{ critical } / $avail->{ all });

