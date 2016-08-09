package ImageCropper::FindAssetURL;

use strict;
use warnings;
use base qw( MT::App );

sub init {
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->add_methods(
        'url' => \&url,
    );
    $app->{default_mode} = 'url';
    $app;
}

sub url {
    my $app = shift;
    my $q = $app->param;
    my $asset_id = $q->param('asset_id');

    return unless $asset_id =~ /^\d+$/;

    # A job with this unique key could not be found in the PQ, which means it's
    # already been processed. Republish so that the correct asset URLs are used.
    if ( ! $app->model('ts_job')->exist({ uniqkey => $asset_id }) ) {
        _republish_file();
    }

    # If this asset ID is still in the queue then the required autocrop assets
    # haven't been built yet. Or, if the asset is not in the queue, this
    # template/page hasn't been republished yet (but was just added). Either
    # way, return the parent asset URL as a default image.
    _return_asset( $asset_id );
}

# Use the referring page's URL to determine exactly what needs to be
# republished, then put it in the queue to be published soon.
sub _republish_file {
    my $app = MT->instance;

    # Determine the referring page's URL. The domain ("server name") needs to
    # be stripped to match how the fileinfo record stores URLs.
    my $url = $ENV{HTTP_REFERER};
    my $server_name = $ENV{SERVER_NAME};
    $url =~ s/.*$server_name(.*)$/$1/;

    my $fi = $app->model('fileinfo')->load({ url => $url });

    if (!$fi) {
        $app->log({
            class    => 'Image Cropper',
            category => 'autocrop_republish',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper was unable to find a fileinfo record '
                . "for the URL `$url`, and was therefore unable to republish "
                . 'this file with now-available assets.',
        });

        return;
    }

    # Does a PQ worker with this fileinfo ID exist already? If so we want to
    # raise the priority; if not we need to insert a worker.
    my $job;
    if ( $job = $app->model('ts_job')->load({ uniqkey => $fi->id }) ) {
        # People are looking at this file, so raise the priority of the job to
        # get it done sooner.
        $job->priority( $job->priority + 1 );
        $job->save
            or die "Couldn't update the priority of this job! " . $job->errstr;
    }
    # Create a PQ worker to get this file republished.
    else {
        my $priority = 5; # A good medium starting point.
        require MT::TheSchwartz;
        require TheSchwartz::Job;
        $job = TheSchwartz::Job->new();
        $job->funcname('MT::Worker::Publish');
        $job->uniqkey($fi->id);
        $job->priority($priority);
        $job->coalesce( ( $fi->blog_id || 0 ) . ':'
                . $$ . ':'
                . $priority . ':'
                . ( time - ( time % 10 ) ) );
        MT::TheSchwartz->insert($job);
    }

}

# Use the assed ID (from the supplied URL) to find the parent asset, to be
# returned as a temporary solution until the desired prototypes are built and
# the page can be republished.
sub _return_asset {
    my ($asset_id, $jobid) = @_;
    my $app = MT->instance;

    my $asset = $app->model('asset')->load({ id => $asset_id });

    # No asset was found? That means the asset was deleted after an
    # AutoCrop job was added... right? Leave the AutoCrop worker to handle
    # that scenario, but note it in the Activity Log.
    if (!$asset) {
        $app->log({
            class    => 'Image Cropper',
            category => 'autocrop_republish',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper was unable to find asset ID '
                . $asset_id . ' while serving from a dynamic URL.',
        });

        # There's no image to return. Should there be some kind of default
        # image for this scenario?

        return;
    }

    # Asset exists, but file was deleted?
    if ( ! -e $asset->file_path) {
        $app->log({
            class    => 'Image Cropper',
            category => 'autocrop_republish',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper found asset ID ' . $asset->id
                . ' from a dynamic URL, but no file was found at the path `'
                . $asset->file_path . '`.',
        });

        # There's no image to return. Should there be some kind of default
        # image for this scenario?

        return;
    }

    open( my $fh, "<", $asset->file_path )
        or return $app->log({
            class    => 'Image Cropper',
            category => 'autocrop_republish',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper found asset ID ' . $asset->id
                . ' from a dynamic URL, but could not read the file found at '
                . 'the path `' . $asset->file_path . '`: ' . $!,
        });

    # Set the header so that the image displays properly.
    $app->set_header( Content_Type => $asset->mime_type );
    $app->send_http_header();

    # Finally, send the asset to the browser.
    # Reset the file pointer
    seek( $fh, 0, 0 );
    while ( read( $fh, my $buffer, 8192 ) ) {
        $app->print($buffer);
    }
    $app->print(''); # print a null string at the end
    close($fh);

    return;
}


1;

__END__
