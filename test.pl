#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;
use autodie;

sub host_state { }
sub service_state { }
sub service_alert { }
sub service_notification { }

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
  'CURRENT HOST STATE' => \&host_state,
  'CURRENT SERVICE STATE' => \&service_state,
  'SERVICE ALERT' => \&service_alert,
  'SERVICE NOTIFICATION' => \&service_notification,
  'SERVICE FLAPPING ALERT' => sub { },
  'HOST ALERT' => \&host_state,
  'EXTERNAL COMMAND' => sub { },
  'SERVICE DOWNTIME ALERT' => sub { },
  'HOST DOWNTIME ALERT' => sub { },
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

