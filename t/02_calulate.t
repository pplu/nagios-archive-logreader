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
    cmp_ok($sla->avail->{ $test }, '==', $tests->{ $test }, "$test is $tests->{ $test } in availability");
  }
}

test_sla([
    "[1525039200] CURRENT SERVICE STATE: host;service;OK;HARD;1;OK plugin output",
  ],
  {
    all => 86400,
    ok => 86400,
  }
);

done_testing;
