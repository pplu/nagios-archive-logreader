#!/usr/bin/env perl

use lib 't/lib';

use Monitoring::SLACalculator;
use StubLines;
use Test::More;

sub test_sla {
  my $description = shift;
  my $lines = shift;
  my $tests = shift;

  my $ini_ts = 1525039200;
  my $last_ts = 1525039200 + 86400;
  my $sla = Monitoring::SLACalculator->new(
    from_ts => $ini_ts,
    to_ts => $last_ts,
    host => 'host',
    service => 'service',
    log_lines => StubLines->new(
      log_lines => $lines,
    )
  );
  
  $sla->process;

  foreach my $test (sort keys %$tests) {
    cmp_ok($sla->avail->{ $test }, '==', $tests->{ $test }, "$test is $tests->{ $test } in availability when $description");
  }
}

test_sla(
  'OK with and without downtime',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] SERVICE DOWNTIME ALERT: host;service;STARTED; Service has entered a period of scheduled downtime",
  ],
  {
    ok => 86400,
    ok_nondowntime => 86400 / 2,
    ok_indowntime => 86400 / 2,
  }
);

my $third_of_day = 86400 / 3;
test_sla(
  'OK with and without downtime',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
    "[" . ( 1525039200 + $third_of_day * 1 ) . "] SERVICE DOWNTIME ALERT: host;service;STARTED; Service has entered a period of scheduled downtime",
    "[" . ( 1525039200 + $third_of_day * 2 ) . "] SERVICE DOWNTIME ALERT: host;service;STOPPED; Service has exited a period of scheduled downtime",
  ],
  {
    ok => 86400,
    ok_nondowntime => $third_of_day * 2,
    ok_indowntime => $third_of_day,
  }
);

test_sla(
  'OK that enters and leaves a service downtime',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
    "[" . ( 1525039200 + $third_of_day * 1 ) . "] SERVICE DOWNTIME ALERT: host;service;STARTED; Service has entered a period of scheduled downtime",
    "[" . ( 1525039200 + $third_of_day * 2 ) . "] SERVICE DOWNTIME ALERT: host;service;CANCELLED; Service has exited a period of scheduled downtime",
  ],
  {
    ok => 86400,
    ok_nondowntime => $third_of_day * 2,
    ok_indowntime => $third_of_day,
  }
);

test_sla(
  'OK that enters and leaves a host downtime',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
    "[" . ( 1525039200 + $third_of_day * 1 ) . "] HOST DOWNTIME ALERT: host;STARTED; Host has entered a period of scheduled downtime",
    "[" . ( 1525039200 + $third_of_day * 1 ) . "] HOST DOWNTIME ALERT: host;STOPPED; Host has exited from a period of scheduled downtime",
  ],
  {
    ok => 86400,
    ok_nondowntime => $third_of_day * 2,
    ok_indowntime => $third_of_day,
  }
);




exit 1;

test_sla(
  'half time warning, half time warning',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] CURRENT SERVICE STATE: host;service;WARNING;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400/2,
    ok_nondowntime => 86400/2,
    warning => 86400/2,
    warning_nondowntime => 86400/2,
  }
);

test_sla(
  'half time warning, half time critical',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] CURRENT SERVICE STATE: host;service;CRITICAL;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400/2,
    critical => 86400/2,
    critical_nondowntime => 86400/2,
  }
);

test_sla(
  'half time warning, half time unknown',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] CURRENT SERVICE STATE: host;service;UNKNOWN;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400/2,
    unknown => 86400/2,
    unknown_nondowntime => 86400/2,
  }
);

test_sla(
  'We ignore soft states',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[1525039205] CURRENT SERVICE STATE: host;service;WARNING;SOFT;1;plugin output",
    "[1525039210] CURRENT SERVICE STATE: host;service;CRITICAL;SOFT;1;plugin output",
    "[1525039215] CURRENT SERVICE STATE: host;service;UNKNOWN;SOFT;1;plugin output",
  ],
  {
    ok => 86400,
  }
);

test_sla(
  'event on the edge of the time window doesn\'t affect result',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . (1525039200 + 86400) . "] CURRENT SERVICE STATE: host;service;CRITICAL;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400,
  }
);

my $five_parts = 86400/5; # We'll produce the five states
test_sla(
  'each state is produced',
  [
    "[" . ( 1525039200 + $five_parts * 1 ) . "] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
    "[" . ( 1525039200 + $five_parts * 2 ) . "] CURRENT SERVICE STATE: host;service;WARNING;HARD;1;plugin output",
    "[" . ( 1525039200 + $five_parts * 3 ) . "] CURRENT SERVICE STATE: host;service;CRITICAL;HARD;1;plugin output",
    "[" . ( 1525039200 + $five_parts * 4 ) . "] CURRENT SERVICE STATE: host;service;UNKNOWN;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => $five_parts,
    ok_nondowntime => $five_parts,
    warning => $five_parts,
    warning_nondowntime => $five_parts,
    critical => $five_parts,
    critical_nondowntime => $five_parts,
    undetermined => $five_parts,
  }
);

test_sla(
  'out of range data (in the past) is not considered',
  [
    "[" . (1525039200 - 100) . "] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
  ],
  {
    all => 86400,
    undetermined => 86400,
  }
);

test_sla(
  'out of range data (in the future) is not considered',
  [
    "[" . (1525039200 + 86400 + 100) . "] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
  ],
  {
    all => 86400,
    undetermined => 86400,
  }
);

done_testing;
