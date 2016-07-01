package ImageCropper::Worker::AutoCrop;

use strict;
use warnings;
use base qw( TheSchwartz::Worker );

use TheSchwartz::Job;
use MT::Blog;
use ImageCropper::Plugin;

sub grab_for    { 120 }
sub max_retries {  3  }
sub retry_delay { 120 }

sub work {
    my $class = shift;
    my TheSchwartz::Job $job = shift;

    my $mt = MT->instance;
    my $TS = MT::TheSchwartz->instance;
    my @jobs;
    push @jobs, $job;

    if ( my $key = $job->coalesce ) {
        while ( my $job = $TS->find_job_with_coalescing_value( $class, $key )) {
            push @jobs, $job;
        }
    }

    foreach $job ( @jobs ) {
        my $hash             = $job->arg;
        my $asset_id         = $job->uniqkey;
        local $mt->{_errstr} = undef;   # Localize the error
        if ( ImageCropper::Plugin::_auto_crop( $asset_id ) ) {
            $job->completed();
        }
        else {
            $job->failed( $mt->errstr );
        }
    }
}

1;

__END__
