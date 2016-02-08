package ImageCropper::Tags;

use strict;
use warnings;

use ImageCropper::Util qw( find_cropped_asset );

# CroppedAsset tag
sub hdlr_cropped_asset {
    my ( $ctx, $args, $cond ) = @_;
    my $l       = $args->{label};

    my $a       = $ctx->stash('asset')
        or return $ctx->_no_asset_error();

    my $blog    =  $ctx->stash('blog')
                || MT->model('blog')->load( $a->blog_id );

    my $blog_id = defined $args->{blog_id}  ? $args->{blog_id}
                : defined $a->blog_id       ? $a->blog_id
                : ref $blog                 ? $blog->id 
                : 0;

    my $out;
    my $cropped_asset = find_cropped_asset($blog_id,$a,$l);
    if ($cropped_asset) {
        local $ctx->{__stash}{'asset'} = $cropped_asset;
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
