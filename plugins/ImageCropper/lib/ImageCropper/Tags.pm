package ImageCropper::Tags;

use strict;
use warnings;

use ImageCropper::Util qw( find_cropped_asset );
use MT::Util qw( caturl );

# CroppedAsset tag
sub hdlr_cropped_asset {
    my ( $ctx, $args, $cond ) = @_;
    my $app     = MT->instance;
    my $label   = $args->{label};
    my $use_dynamic = $args->{use_dynamic_url} || 0;
    # If `use_dynamic_url` is specified then `no_autocrop` is, by necessity,
    # specified. Otherwise false, so that the tag's "else" statement can work.
    my $no_autocrop = $args->{no_autocrop} ? 1
        : $use_dynamic ? 1 : 0;

    my $a       = $ctx->stash('asset')
        or return $ctx->_no_asset_error();

    my $blog    =  $ctx->stash('blog')
                || MT->model('blog')->load({ id => $a->blog_id });

    my $blog_id = defined $args->{blog_id}  ? $args->{blog_id}
                : defined $a->blog_id       ? $a->blog_id
                : ref $blog                 ? $blog->id
                : 0;

    my $out;
    my $cropped_asset = find_cropped_asset($blog_id, $a, $label, $no_autocrop);
    if ($cropped_asset) {
        local $ctx->{__stash}{'asset'} = $cropped_asset;

        # Is the desired prototype AutoCrop-enabled, and is there an AutoCrop
        # job in the queue? If so, we need to supply a new dynamic URL to use
        # the `find_asset_url.cgi` interface. (And if there is no AutoCrop job
        # that means the asset already exists, or it's not automatically
        # created and this URL rewrite is skipped.)
        my $prototype_terms = {
            blog_id  => $blog_id,
            label    => $label,
            autocrop => 1,
        };
        my $worker = $app->model('ts_funcmap')->load({
                funcname => 'ImageCropper::Worker::AutoCrop',
            }) or die "Image Cropper AutoCrop worker is missing?";
        my $job_terms = {
            funcid  => $worker->funcid,
            uniqkey => $a->id,
        };

        if (
            $use_dynamic
            && $app->model('thumbnail_prototype')->exist( $prototype_terms )
            && $app->model('ts_job')->exist( $job_terms )
        ) {
            $ctx->{__stash}{asset}->url(
                caturl(
                    $app->config->CGIPath,
                    $app->component('ImageCropper')->envelope,
                    $app->config->FindAssetURLScript
                        . '?asset_id=' . $a->id,
                )
            );
        }

        defined( $out = $ctx->slurp( $args, $cond ) ) or return;
        return $out;
    }
    return _hdlr_pass_tokens_else(@_);
}

sub _hdlr_pass_tokens_else {
    my ( $ctx, $args, $cond ) = @_;
    my $b = $ctx->stash('builder');
    my $out;
    defined( $out = $b->build( $ctx, $ctx->stash('tokens_else'), $cond ) )
        or return $ctx->error( $b->errstr );
    return $out;
}

# DefaultCroppedImageText tag
sub hdlr_default_text {
    my ( $ctx, $args, $cond ) = @_;
    my $cfg = $ctx->{config};
    return $cfg->DefaultCroppedImageText;
}

1;

__END__
