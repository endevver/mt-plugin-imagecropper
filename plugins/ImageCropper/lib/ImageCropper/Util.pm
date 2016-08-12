package ImageCropper::Util;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( crop_filename crop_image annotate file_size find_cropped_asset );

use Carp qw( croak );
use Scalar::Util qw( blessed looks_like_number );
use Try::Tiny;

sub file_size {
    my $a     = shift;
    my $sizef = '? KB';
    if ( $a->file_path && ( -f $a->file_path ) ) {
        my @stat = stat( $a->file_path );
        my $size = $stat[7];
        if ( $size < 1024 ) {
            $sizef = sprintf( "%d Bytes", $size );
        }
        elsif ( $size < 1024000 ) {
            $sizef = sprintf( "%.1f KB", $size / 1024 );
        }
        else {
            $sizef = sprintf( "%.1f MB", $size / 1024000 );
        }
    }
    return $sizef;
}

sub crop_image {
    my $image = shift;
    my %param = @_;
    my ( $w, $h, $x, $y, $type, $qual ) =
      @param{qw( Width Height X Y Type quality)};
    my $magick = $image->{magick};
    my $err    = $magick->Crop(
        'width'  => $w,
        'height' => $h,
        'x'      => $x,
        'y'      => $y,
    );
    if ($qual) {
        $magick->Set( quality => $qual );
    }
    return $image->error(
        MT->translate(
            "Error cropping a [_1]x[_2] image at [_3],[_4] failed: [_5]",
            $w, $h, $x, $y, $err
        )
    ) if $err;

    ## Remove page offsets from the original image, per this thread:
    ## http://studio.imagemagick.org/pipermail/magick-users/2003-September/010803.html
    $magick->Set( page   => '+0+0' );
    $magick->Set( magick => $type );
    ( $image->{width}, $image->{height} ) = ( $w, $h );
    return wantarray
      ? ( $magick->ImageToBlob, $w, $h )
      : $magick->ImageToBlob;
}

sub annotate {
    my $image = shift;
    my %param = @_;
    my ( $txt, $loc, $ori, $size, $family ) =
      @param{qw( text location rotation size family )};
    my $magick = $image->{magick};
    my ( $rot, $x ) = ( 0, 0 );
    if ( $ori eq 'Vertical' ) {
        if ( $loc eq 'NorthWest' ) {
            $rot = 90;
            $x   = 12;
        }
        elsif ( $loc eq 'NorthEast' ) {
            $rot = 270;
            $x   = 12;
        }
        elsif ( $loc eq 'SouthWest' ) {
            $rot = 270;
            $x   = 12;
        }
        elsif ( $loc eq 'SouthEast' ) {
            $rot = 90;
            $x   = 12;
        }
    }
    MT->log( {
            message =>
              "Annotating image with text: '$txt' ($loc, $rot degrees, $family at $size pt.)"
        }
    );
    my $err = $magick->Annotate(
        'pen'       => 'white',
        'font'      => $family,
        'pointsize' => $size,
        'text'      => $txt,
        'gravity'   => $loc,
        'rotate'    => $rot,
        'x'         => $x,
    );
    MT->log("Error annotating image with $txt: $err") if $err;

    return wantarray
      ? ( $magick->ImageToBlob )
      : $magick->ImageToBlob;
}

sub crop_filename {
    my $asset   = shift;
    my (%param) = @_;
    my $file    = $asset->file_name or return;

    require MT::Util;
    my $format = $param{Format}    || MT->translate('%f-cropped-proto-%p%x');
    my $proto  = $param{Prototype} || '0';
    $file =~ s/\.\w+$//;
    my $base = File::Basename::basename($file);
    my $ext = lc( $param{Type} ) || $asset->file_ext || '';
    $ext = '.' . $ext;
    my $id = $asset->id;
    $format =~ s/%p/$proto/g;
    $format =~ s/%f/$base/g;
    $format =~ s/%i/$id/g;
    $format =~ s/%x/$ext/g;
    return split( /[\/\\]/, $format );
}

sub find_prototype_id {
    my ( $ts, $label ) = @_;
    return undef unless $ts;
    my $protos = MT->registry('template_sets')->{$ts}->{thumbnail_prototypes};
    foreach my $proto ( keys %$protos ) {
        my $l = $protos->{$proto}->{label};
        return $proto if $l
                      && $l ne ''
                      && &{$l} eq $label;
    }
}

sub prototype_key {
    my ( $blog_id, $label ) = @_;
    croak "No valid blog_id provided" unless looks_like_number($blog_id);
    croak "No label specified"        unless $label;

    return try {
        my $Prototype       = MT->model('thumbnail_prototype');
        my $prototype_terms = { blog_id => $blog_id, label => $label };
        my $prototype       = $Prototype->load($prototype_terms);
        $prototype->basename ? $prototype->basename
                             : 'custom_' . $prototype->id;
    }
    catch {
        my $blog = MT->model('blog')->load({ id => $blog_id });
        my $ts   = $blog->template_set;
        my $id   = find_prototype_id( $ts, $label );
        $id ? $ts . "___" . $id : undef;
    };
}

sub find_cropped_asset {
    shift if $_[0] eq __PACKAGE__; # supports class or method invocation
    my ( $blog_id, $asset, $label, $no_autocrop ) = @_;
    ( $asset, my $asset_id ) = ( undef, $asset ) if looks_like_number( $asset );

    require MT::Memcached;
    my $cache         = MT::Memcached->instance;
    my $cache_key     = join(':', 'cropped_asset', $blog_id,
                                  ( $asset_id || $asset->id ), $label );
    $cache_key =~ s! !_!g;
    my $cropped_asset = $cache->get( $cache_key );
    return $cropped_asset if $cropped_asset;

    # Die if we're not provided the information we need to do our job
    my $Asset = MT->model('asset');
    croak "No valid asset_id or asset provided"
        unless $asset_id || try { $asset->isa($Asset) };

    # Cropped assets are created with the parent asset, so make sure the parent
    # is being used now, too, so that the proper cropped asset can be found.
    $asset = $Asset->load({ id => $asset_id })
        or croak "Asset ID $asset_id could not be loaded."
            if defined $asset_id;

    # We loaded a child asset above; we want the parent. The while statement
    # lets us get to the "real" parent if this asset is a child of a child of a
    # child, etc.
    while ( $asset->parent ) {
        $asset = $Asset->load({ id => $asset->parent })
            or croak 'Could not load parent asset.';
    }

    my $key = prototype_key( $blog_id, $label )
        or croak 'Unable to find a thumbnail prototype with the label `'
            . $label . '`.';

    my $terms = { prototype_key => $key, asset_id => $asset->id };
    if ( my $map = MT->model('thumbnail_prototype_map')->load($terms) ) {
        $cropped_asset = $Asset->load({ id => $map->cropped_asset_id });
            # May be undef which is okay
    }

    if ( $cropped_asset ) {
        no warnings 'once';
        print STDERR "Memcache set: $cache_key = $cropped_asset\n"
            if $MT::DebugMode & 256;
        $cache->set( $cache_key => $cropped_asset );
    }
    else {
        # If the desired prototype supports autocrop, then insert a job to build
        # the image.
        my $Prototype       = MT->model('thumbnail_prototype');
        my $prototype_terms = { blog_id => $blog_id, label => $label };
        my $prototype        = $Prototype->load($prototype_terms);
        if (
            $prototype
            && $prototype->autocrop
            and $asset ||= $Asset->load({ id => $asset_id })
        ) {
            require ImageCropper::Plugin;
            ImageCropper::Plugin::insert_auto_crop_job( $asset );
        }

        # If $no_autocrop is true then we want to provide a valid asset *right
        # now*, not whenever the autocrop job is finished. The parent asset
        # will do.
        $cropped_asset = $asset
            if $no_autocrop;
    }

    # It's ok if $cropped_asset is undefined: that means there's no cropped
    # image for the desired prototype. That's not necessarily a problem in that
    # it can be handled through templating and the `Else` tag that Image
    # Cropper provides for the `CroppedAsset` block tag.
    return $cropped_asset;
}

1;
