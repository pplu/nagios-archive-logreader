package Monitoring::NagiosArchiveLogReader {
  use Moose;

  use IO::Handle;

  has fh => (is => 'ro', isa => 'FileHandle', default => sub { IO::Handle->new_from_fd(0, 'r') });

  sub get {
    my $self = shift;
    my $line = $self->fh->getline;
    chomp $line;
    return $line;
  }

  __PACKAGE__->meta->make_immutable;
}
1;
