package ImageCropper::Util;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw( crop_filename crop_image annotate file_size find_prototype_id find_cropped_asset );

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
    foreach ( keys %$protos ) {
        my $l = $protos->{$_}->{label};
        return $_ if ( $l && $l ne '' && &{$l} eq $label );
    }
}

sub find_cropped_asset {
    my ( $blog_id, $asset, $label ) = @_;
    $blog_id    = 0 unless ( $blog_id && $blog_id ne '' );
    return undef unless $blog_id;
    my $blog    = MT->model('blog')->load($blog_id);
    my $ts      = $blog->template_set;

    my $prototype = MT->model('thumbnail_prototype')->load({
        blog_id => $blog_id,
        label   => $label,
    });

    my $map;
    if ($prototype) {
        my $key = defined $prototype->basename
            ? $prototype->basename
            : 'custom_' . $prototype->id;

        $map = MT->model('thumbnail_prototype_map')->load({
            prototype_key => $key,
            asset_id      => $asset->id,
        });
    }
    elsif ( my $id = find_prototype_id( $ts, $label ) ) {
        # MT->log({ message => "prototype not found, consulted registry: " . $id });
        $map = MT->model('thumbnail_prototype_map')->load({
            prototype_key => $ts . "___" . $id,
            asset_id      => $asset->id,
        });
    }

    if ($map) {
        return MT->model('asset')->load( $map->cropped_asset_id );
    }
    return undef;
}

1;
