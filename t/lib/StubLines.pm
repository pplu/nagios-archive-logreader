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
1;
