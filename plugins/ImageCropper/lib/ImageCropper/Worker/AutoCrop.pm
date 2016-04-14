package ImageCropper::Worker::AutoCrop;

use strict;
use warnings;
use base qw( TheSchwartz::Worker );

use TheSchwartz::Job;
use MT::Blog;
use ImageCropper::Plugin;

sub work {
    my $class = shift;
    my TheSchwartz::Job $job = shift;

    my $mt = MT->instance;

    my @jobs;
    push @jobs, $job;

    if ( my $key = $job->coalesce ) {
        while (
            my $job = MT::TheSchwartz->instance->find_job_with_coalescing_value(
                $class, $key
            )
        ) {
            push @jobs, $job;
        }
    }

    foreach $job (@jobs) {
        my $hash     = $job->arg;
        my $asset_id = $job->uniqkey;

        ImageCropper::Plugin::_auto_crop( $asset_id );

        $job->completed();
    }
}

sub grab_for    {120}
sub max_retries {3}
sub retry_delay {120}

1;

__END__
