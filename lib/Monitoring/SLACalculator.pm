package Monitoring::SLACalculator {
  use Moose;
  use autodie;

  use Monitoring::NagiosArchiveLogReader;

  has host    => (is => 'ro', isa => 'Str', required => 1);
  has service => (is => 'ro', isa => 'Str', required => 1);
  has from_ts => (is => 'ro', isa => 'Int', required => 1);
  has to_ts   => (is => 'ro', isa => 'Int', required => 1);

  has _last_event_state => (is => 'rw', isa => 'Str', default => 'UNDETERMINED');
  has _last_event_ts    => (is => 'rw', isa => 'Int', lazy => 1, default => sub { shift->from_ts });
  has _in_downtime      => (is => 'rw', isa => 'Bool', default => 0);

  has avail => (is => 'ro', isa => 'HashRef[Int]', default => sub {
    {
      all => 0,
      undetermined => 0,
      ok => 0,
      ok_indowntime => 0,
      ok_nondowntime => 0,
      warning => 0,
      warning_indowntime => 0,
      warning_nondowntime => 0,
      unknown => 0,
      unknown_indowntime => 0,
      unknown_nondowntime => 0,
      critical => 0,
      critical_indowntime => 0,
      critical_nondowtime => 0,
    }
  });

  has handlers => (is => 'ro', isa => 'HashRef[CodeRef]', default => sub {
    {
      'LOG ROTATION' => sub { },
      'LOG VERSION' => sub { },
    
      'HOST ALERT' => sub { },
      'CURRENT HOST STATE' => sub { },
    
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
  });

  has log_lines => (is => 'ro', lazy => 1, default => sub {
    my $self = shift;
    Monitoring::NagiosArchiveLogReader->new(
      from_ts => $self->from_ts,
      to_ts => $self->to_ts,
    );
  });

  sub ts_not_in_range {
    my ($self, $ts) = @_;
    return 1 if ($ts < $self->from_ts);
    return 1 if ($ts > $self->to_ts);
  }

  sub service_state { 
    my ($self, $content, undef, $ts) = @_;
  
    return if ($self->ts_not_in_range($ts));
 
    my $state = {};
    ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ state_type }, undef, $state->{ output }) = split /;/, $content, 6;
  
    # Only process if we're scanning for this host and service
    return if (($state->{ host } ne $self->host) or ($state->{ service } ne $self->service));
  
    return if ($state->{ state_type } ne 'HARD');
    
    my $delta_t = $ts - $self->_last_event_ts;
    $self->add_to_availability($delta_t);
  
    $self->_last_event_state($state->{ state });
    $self->_last_event_ts($ts);
  }
  
  sub add_to_availability {
    my ($self, $duration) = @_;
    my $avail = $self->avail;
    my $last_event_state = $self->_last_event_state;
  
    $avail->{ all } += $duration;
  
    my $suffix = $self->_in_downtime ? 'indowntime' : 'nondowntime';
    my $state = lc($last_event_state);

    $avail->{  $state }          += $duration;
    $avail->{ "${state}_${suffix}" } += $duration if ($last_event_state ne 'UNDETERMINED');
  }
  
  sub host_downtime { 
    my ($self, $content, undef, $ts) = @_;
  
    return if ($self->ts_not_in_range($ts));
  
    my $state = {};
    ($state->{ host }, $state->{ state }, $state->{ output }) = split /;/, $content, 3;
  
    # Only process if we're scanning for this host
    return if ($state->{ host } ne $self->host);
  
    # add the time till the downtime event to the availability
    my $delta_t = $ts - $self->_last_event_ts;
    $self->add_to_availability($delta_t);
    $self->_last_event_ts($ts);
  
    if ($state->{ state } eq 'STOPPED') {
      $self->_in_downtime(0);
    } elsif ($state->{ state } eq 'CANCELLED') {
      $self->_in_downtime(0);
    } elsif ($state->{ state } eq 'STARTED') {
      $self->_in_downtime(1);
    } else {
      die "Unknown state $state->{ state }";
    }
  }

  sub service_downtime { 
    my ($self, $content, undef, $ts) = @_;
  
    return if ($self->ts_not_in_range($ts));
  
    my $state = {};
    ($state->{ host }, $state->{ service }, $state->{ state }, $state->{ output }) = split /;/, $content, 4;
  
    # Only process if we're scanning for this host and service
    return if (($state->{ host } ne $self->host) or ($state->{ service } ne $self->service));
  
    # add the time till the downtime event to the availability
    my $delta_t = $ts - $self->_last_event_ts;
    $self->add_to_availability($delta_t);
    $self->_last_event_ts($ts);
  
    if ($state->{ state } eq 'STOPPED') {
      $self->_in_downtime(0);
    } elsif ($state->{ state } eq 'CANCELLED') {
      $self->_in_downtime(0);
    } elsif ($state->{ state } eq 'STARTED') {
      $self->_in_downtime(1);
    } else {
      die "Unknown state $state->{ state }";
    }
  }
  
  sub end_file {
    my ($self, $ts) = @_;
  
    my $delta_t = $ts - $self->_last_event_ts;
    $self->add_to_availability($delta_t);
    $self->_last_event_ts($ts);
  }
  
  sub no_type {
    my ($self, $content, $ts) = @_;
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
  
  sub process {
    my $self = shift;

    while (my $line = $self->log_lines->get()) {
      if (my ($ts, $type, $content) = ($line =~ m/\[(\d+)\] ([A-Za-z_ ]+?): (.*)/)) {
        my $handler = $self->handlers->{ $type };
        die "No handler for $type in\n$line" if (not defined $handler);
        $self->handlers->{ $type }->($self, $content, $type, $ts);
      } elsif (my ($ts_2, $content_2) = ($line =~ m/\[(\d+)\] (.*)/)) {
        $self->handlers->{ no_type }->($self, $content_2, $ts_2);
      } else {
        die "Unrecognized log line '$line'";  
      }
    }
    $self->end_file($self->to_ts);
  }

  __PACKAGE__->meta->make_immutable;
}
1;
