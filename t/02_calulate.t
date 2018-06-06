#!/usr/bin/env perl

use lib 't/lib';

use Monitoring::SLACalculator;
use StubLines;
use Test::More;

package StubLines {
  use Moose;
  has log_lines => (is => 'ro', isa => 'ArrayRef[Str]', required => 1);
  has _i => (is => 'rw', isa => 'Int', default => 0);
  sub get {
    my $self = shift;
    my $line = $self->log_lines->[ $self->_i ];
    $self->_i($self->_i + 1);
    return $line;
  }
}

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

  foreach my $test (keys %$tests) {
    cmp_ok($sla->avail->{ $test }, '==', $tests->{ $test }, "$test is $tests->{ $test } in availability when $description");
  }
}

test_sla(
  'No data',
  [
  ],
  {
    all => 86400,
    undetermined => 86400,
  }
);

test_sla(
  'Not looking for that host',
  [
    "[1525039200] CURRENT SERVICE STATE: wronghost;service;OK;HARD;1;plugin output",
  ],
  {
    all => 86400,
    undetermined => 86400,
  }
);

test_sla(
  'Not looking for that service',
  [
    "[1525039200] CURRENT SERVICE STATE: host;wrongservice;OK;HARD;1;plugin output",
  ],
  {
    all => 86400,
    undetermined => 86400,
  }
);

test_sla(
  'Correct host and service only one OK line',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400,
  }
);

test_sla(
  'Two OK lines',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] CURRENT SERVICE STATE: host;service;OK;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400,
  }
);

test_sla(
  'half time warning, half time warning',
  [
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
    "[" . ( 1525039200 + 86400/2 ) . "] CURRENT SERVICE STATE: host;service;WARNING;HARD;1;plugin output",
  ],
  {
    all => 86400,
    ok => 86400/2,
    warning => 86400/2,
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
    warning => $five_parts,
    critical => $five_parts,
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
