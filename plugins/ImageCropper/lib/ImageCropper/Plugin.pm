# Image Cropper Plugin for Movable Type and Melody
# Copyright (C) 2009 Endevver, LLC.

package ImageCropper::Plugin;

use strict;
use warnings;

use Scalar::Util qw( looks_like_number );
use Carp qw( croak longmess confess );
use Sub::Install;

use MT::Util qw( relative_date     ts2epoch format_ts    caturl    encode_url
                 offset_time_list  epoch2ts offset_time  dirify );
use ImageCropper::Util qw( crop_filename crop_image annotate file_size find_cropped_asset );

use MT::Log::Log4perl qw( l4mtdump ); use Log::Log4perl qw( :resurrect );
my $logger ||= MT::Log::Log4perl->new();

my %target;

sub post_remove_asset {
    my ( $cb, $obj ) = @_;

    my @maps = MT->model('thumbnail_prototype_map')->load({
        asset_id => $obj->id,
    });
    foreach my $map (@maps) {
        my $a = MT->model('asset')->load({ id => $map->cropped_asset_id });
        $a->remove   if $a;
        $map->remove if $map;
    }

    my $ptmap = MT->model('thumbnail_prototype_map')->load({
        cropped_asset_id => $obj->id,
    });
    $ptmap->remove if $ptmap;

    return 1;
}

# METHOD: init_app
#
# A callback handler which hooks into the MT::App::CMS::init_app callback
# in order to override and wrap MT::CMS::Asset::complete_upload
sub init_app {
    my ( $plugin, $app ) = @_;
    ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    # Do nothing unless the current app is our target app
    return unless ref $app and $app->isa('MT::App::CMS');

    # This plugin operates by overriding the method
    # (MT::CMS::Asset::complete_upload)
    %target = (
        module => 'MT::CMS::Asset',
        method => 'complete_upload',
        subref => undef
    );

    # Make sure that our app module has the method we're looking for
    # and grab a reference to it if so.
    eval "require $target{module};"
      or die "Could not require $target{module}";
    $target{subref} = $target{module}->can( $target{method} );

    # Throw an error and quit if we could not find our target method
    unless ( $target{subref} ) {
        my $err =
          sprintf( '%s plugin initialization error: %s method not found. '
              . 'This may have been caused by changes introduced by a '
              . 'Movable Type upgrade.',
            __PACKAGE__, join( '::', $target{module}, $target{method} ) );
        $app->log( {
                class    => 'system',
                category => 'plugin',
                level    => MT::Log::ERROR(),
                message  => $err,
            }
        );
        return undef;    # We simply can't go on....
    }

    ###l4p $logger->debug( 'Overriding method: '
    ###l4p               . join('::', $target{module}, $target{method}));

    # Override the target method with our own version
    require Sub::Install;
    Sub::Install::reinstall_sub( {
            code => \&complete_upload_wrapper,
            into => $target{module},
            as   => $target{method},
        }
    );
}

sub complete_upload_wrapper {
    my $app      = shift;
    my $asset_id = $app->param('id');

    ###l4p $logger     ||= MT::Log->get_logger();  $logger->trace();

    # Call the original method to perform the work
    $target{subref}->( $app, @_ );

    # Alter the redirect location from list_assets
    # to manage_thumbnails for the uploaded asset
    if ( $app->{redirect} =~ m{__mode=list_assets} ) {
        return $app->redirect(
            $app->uri(
                'mode' => 'view',
                'args' => {
                    'from'        => 'view',
                    '_type'       => 'asset',
                    'id'          => $asset_id,
                    'blog_id'     => $app->param('blog_id'),
                    'return_args' => $app->return_args,
                    'magic_token' => $app->param('magic_token')
                }
            )
        );
    }
    return;
}

sub find_prototype_id {
    my ( $ctx, $label ) = @_;
    my $blog = $ctx->stash('blog');
    my $ts   = $blog->template_set;
    return undef unless $ts;
    my $protos = MT->registry('template_sets')->{$ts}->{thumbnail_prototypes};
    foreach ( keys %$protos ) {
        my $l = $protos->{$_}->{label};
        return $_ if ( $l && $l ne '' && &{$l} eq $label );
    }
}

sub load_ts_prototype {
    my $app = shift;
    my ($key) = @_;
    my ( $ts, $id ) = split( '___', $key );
    return $app->registry('template_sets')->{$ts}->{thumbnail_prototypes}
      ->{$id};
}

# Create prototypes from template set/theme definitions. This is run when
# visiting the Manually Generate Thumbnails screen and when choosing to
# auto-crop images.
sub content_action_import_ts_prototypes {
    my $app  = MT->instance;
    my $blog = $app->blog;

    _import_ts_prototypes( $blog );

    $app->redirect(
        $app->{cfg}->CGIPath . $app->{cfg}->AdminScript
        . "?__mode=list&_type=thumbnail_prototype&blog_id=" . $blog->id
    );
}

# If this blog uses a theme and if the theme has prototypes defined, show the
# link to provide the opportunity to import them.
sub import_prototypes_condition {
    my ($app) = MT->instance;

    return 0 unless $app->blog && $app->blog->id;

    my $ts = $app->blog->template_set;
    return 1 if $ts
        && $app->registry('template_sets')->{$ts}->{thumbnail_prototypes};
}

# The list action on the Manage Blogs screen makes it easy to import quickly.
sub list_action_import_ts_prototypes {
    my ($app) = @_;
    $app->validate_magic or return;
    my @blog_ids = $app->param('id');

    for my $blog_id (@blog_ids) {
        my $blog = $app->model('blog')->load({ id => $blog_id })
            or next;
        _import_ts_prototypes( $blog );
    }

    $app->call_return;
}

# When a theme is re-applied, import any available prototypes.
sub post_apply_theme_callback {
    my ($cb, $theme, $blog) = @_;
    _import_ts_prototypes( $blog );
}

# Import any prototypes associated with this blog and theme.
sub _import_ts_prototypes {
    my ($blog) = @_;
    my $app    = MT->instance;

    return unless $blog->template_set;

    my $ts = $blog->template_set;
    my $ps = $app->registry('template_sets')->{$ts}->{thumbnail_prototypes};
    foreach ( keys %$ps ) {
        my $p   = $ps->{$_};
        my $key = dirify( $ts . '__' . $_ );

        # If the required values for this prototype are missing, give up.
        next unless $p->{label} && ($p->{max_width} || $p->{max_height});

        # Save this theme-based prototype for future use.
        unless (
            $app->model('thumbnail_prototype')->exist({
                blog_id  => $blog->id,
                basename => $key,
            })
        ) {
            my $prototype = $app->model('thumbnail_prototype')->new();
            $prototype->blog_id(    $blog->id        );
            $prototype->label(      &{ $p->{label} } );
            $prototype->basename(   $key             );
            $prototype->max_width(  $p->{max_width}  );
            $prototype->max_height( $p->{max_height} );
            $prototype->autocrop(   $p->{autocrop}   );

            $prototype->save or die $prototype->errstr;

            $app->log({
                blog_id  => $blog->id,
                category => 'import',
                class    => 'Image Cropper',
                level    => $app->model('log')->INFO(),
                message  => 'Image Cropper has imported the thumbnail '
                    . 'prototype &ldquo;' . &{ $p->{label} }
                    . '&rdquo; from the theme &ldquo;' . $ts . '.&rdquo;'
            });
        }
    }
}

# The manuall generate thumbnails screen.
sub gen_thumbnails_start {
    my $app = shift;
    my ($param) = @_ || {};
    $app->validate_magic or return;

    # We want to work with the parent asset only. Is this the parent? If not,
    # find it.
    my $id  = int($app->param('id'))
        or return $app->error('No "id" parameter provided for asset');
    my $obj = $app->model('asset')->load({ id => $id })
        or return $app->error('Could not load asset.');

    while ( $obj->parent ) {
        # We loaded a child asset above; we want the parent.
        $obj = $app->model('asset')->load({ id => $obj->parent })
            or return $app->error('Could not load parent asset.');
    }

    my ( $bw, $bh ) = _box_dim($obj);

    my @protos;
    my @custom = $app->model('thumbnail_prototype')->load(
        { blog_id => $app->blog->id }, { sort => 'label' }
    );
    foreach (@custom) {
        push @protos, {
            id         => $_->id,
            key        => ($_->basename ? $_->basename : 'custom_' . $_->id),
            label      => $_->label,
            max_width  => $_->max_width,
            max_height => $_->max_height,
        };
    }

    my @loop;
    foreach my $p (@protos) {
        # Look for prototype mappings. Theme-built prototypes are saved as
        # dirified basenames, but previously they just used double colons to
        # join values which is messy and causes JS trouble. But, since maps may
        # exist to these old-style keys, look for any in addition to the new
        # style.
        my $old_style_key = $p->{key};
        $old_style_key =~ s/__/::/;

        my $map = MT->model('thumbnail_prototype_map')->load({
            asset_id      => $obj->id,
            prototype_key => [$p->{key}, $old_style_key],
        });

        my ( $url, $x, $y, $w, $h, $size );
        if ($map) {
            $x = $map->cropped_x;
            $y = $map->cropped_y;
            $w = $map->cropped_w;
            $h = $map->cropped_h;
            my $a = MT->model('asset')->load({ id => $map->cropped_asset_id });
            if ($a) {
                $url  = $a->url;
                $size = file_size($a);
            }
        }
        push @loop, {
            proto_id      => $p->{id},
            proto_key     => $p->{key},
            proto_label   => $p->{label},
            thumbnail_url => $url,
            cropped_x     => $x,
            cropped_y     => $y,
            cropped_w     => $w,
            cropped_h     => $h,
            cropped_size  => $size,
            max_width     => $p->{max_width},
            max_height    => $p->{max_height},
            is_tall       => $p->{max_height} > $p->{max_width},
            # 175x135 thumbnail preview area
            smaller_vp => ( $p->{max_height} < 135 && $p->{max_width} < 175 ),
        };
    }
    $param->{prototype_loop} = \@loop if @loop;
    $param->{box_width}      = $bw;
    $param->{box_height}     = $bh;
    $param->{actual_width}   = $obj->image_width;
    $param->{actual_height}  = $obj->image_height;
    $param->{has_prototypes} = $#loop >= 0;
    $param->{asset_label}    = defined $obj->label ? $obj->label
                                                   : $obj->file_name;

    my $plugin = MT->component('imagecropper');
    $param->{annotation_size} = $plugin->get_config_value(
        'annotate_fontsize',
        'blog:' . $obj->blog_id
    );
    $param->{default_quality} = $plugin->get_config_value(
        'default_quality',
        'blog:' . $obj->blog_id
    );

    my $tmpl = $app->load_tmpl( 'start.tmpl', $param );
    my $ctx = $tmpl->context;
    $ctx->stash( 'asset', $obj );
    return $tmpl;
}

# Delete a cropped thumnbnail from the manually create interface, clicking a
# trash can icon in the prototype preview area.
sub delete_crop {
    my $app  = shift;
    my $blog = $app->blog;
    my $id   = $app->param('id');
    my $key  = $app->param('prototype');

    _remove_old_asset({
        asset_id => $id,
        key      => $key,
        blog_id  => $blog->id,
    });

    my $result = {
        proto_key => $key,
        success   => 1,
    };

    return _send_json_response( $app, $result );
}

# User has defined a crop area dn clicked the "Crop" button. Do the actual
# crop/resize to create a thumbnail.
sub crop {
    my $app  = shift;
    my $id   = $app->param('asset');
    my $blog = $app->blog;

    my $asset = $app->model('asset')->load({ id => $id })
        or return { error => "Asset ID $id could not be loaded." };

    my $result = _create_thumbnail({
        asset          => $asset,
        prototype_key  => $app->param('key'),
        w              => $app->param('w'),
        h              => $app->param('h'),
        x              => $app->param('x'),
        y              => $app->param('y'),
        quality        => $app->param('quality'),
        annotate       => $app->param('annotate'),
        text           => $app->param('text'),
        text_size      => $app->param('text_size'),
        text_location  => $app->param('text_loc'),
        text_rotation  => $app->param('text_rot'),
    });

    return _send_json_response( $app, $result );
}

sub _send_json_response {
    my ( $app, $result ) = @_;
    require JSON;
    my $json = JSON::objToJson($result);
    $app->send_http_header("");
    $app->print($json);
    return $app->{no_print_body} = 1;
    return undef;
}

sub _box_dim {
    my ($obj) = @_;
    my ( $box_w, $box_h );
    if ( $obj->image_width > 900 ) {

        #   x    h
        #  --- = - => (900*h) / w = x
        #  900   w
        $box_w = 900;
        $box_h = int( ( 900 * $obj->image_height ) / $obj->image_width );
    }
    else {
        $box_w = $obj->image_width;
        $box_h = $obj->image_height;
    }
    return ( $box_w, $box_h );
}

# Automatically crop/resize to create thumbnails from the Edit Asset page; user
# clicked the Automatically Generate Thumbnails page action.
sub page_action_auto_crop {
    my ($app) = @_;
    my $id    = $app->param('id');

    $app->validate_magic or return;

    return $app->error('Invalid ID parameter')
        unless looks_like_number( $id );

    my $asset = $app->model('asset')->load({id => $id})
        or return;
    my $cropped = insert_auto_crop_job( $asset );

    $app->add_return_arg( thumbnails_created => $cropped );
    return $app->call_return;
}

# Can the "Automatically Generate Thumbnails" and "Generate Thumbnails" page
# actions be displayed for this asset? Check that it's an image asset first.
sub page_action_condition {
    my ( $app )  = MT->instance;
    my $asset_id = $app->param('id');

    return 1 if $app->model('asset')->exist({
        id    => $asset_id,
        class => ['image', 'photo'],
    });

    return 0;
}

# Automatically crop/resize to create thumbnails from the Manage Assets page;
# user selected images and chose the Automatically Generate Thumbnails list
# action.
sub list_action_auto_crop {
    my ( $app )   = @_;
    my @asset_ids = $app->param('id');

    $app->validate_magic or return;

    return $app->error( 'Invalid ID parameter found in list' )
        if grep { ! looks_like_number( $_ ) } @asset_ids;

    my ( @cropped, $had_errors );
    for my $asset_id ( @asset_ids ) {
        local $app->{_errstr} = undef;   # Localize the error
        my $asset = $app->model('asset')->load({id => $asset_id})
            or next;
        my $batch = insert_auto_crop_job( $asset );
        if ( defined $batch ) {
            push( @cropped, $batch );
        }
        else {
            $had_errors = 1;
        }
    }

    $app->add_return_arg( thumbnails_created => scalar @cropped,
                          had_errors         => $had_errors || 0 );
                          ### FIXME Handle had_errors in the templates
    $app->call_return;
}

# Auto crop expects an asset ID and creates any thumbnails that need to be
# created based on all prototypes in the blog that are marked for autocrop.
sub _auto_crop {
    my ($asset_id) = @_;
    my $app        = MT->instance;

    # We want to work with the parent asset only. Is this the parent? If not,
    # find it.
    my $asset = $app->model('asset')->load({
        id    => $asset_id,
        class => ['image', 'photo'],
    });

    if ( ! $asset ) {
        my $msg = 'Image Cropper is unable to load the asset ID ' . $asset_id
            . ' for processing with Auto-Crop-enabled Prototypes.';
        $app->log({
            category => 'load',
            class    => 'Image Cropper',
            level    => $app->model('log')->ERROR(),
            message  => $msg,
        });
        return $app->error($msg);
    }

    while ( $asset->parent ) {
        # We loaded a child asset above; we want the parent.
        $asset = $app->model('asset')->load({
            id => $asset->parent,
        });
        unless ( $asset ) {
            my $msg = 'Image Cropper is unable to load asset ID '
                    . $asset->parent . ', the parent of asset ID '
                    . $asset_id. '; child assets will not be created based on '
                    . 'Auto-Crop-enabled Prototypes.';
            $app->log({
                category => 'load',
                class    => 'Image Cropper',
                level    => $app->model('log')->ERROR(),
                message  => $msg,
            });
            return $app->error($msg);
        }
    }

    # The file needs to exist for us to do anything with it!
    if ( ! -f $asset->file_path ) {
        my $msg = 'Image Cropper is unable to load the file '
                . $asset->file_path . ' for asset ID ' . $asset->id . '.';
        $app->log({
            blog_id  => $asset->blog_id,
            category => 'load',
            class    => 'Image Cropper',
            level    => $app->model('log')->ERROR(),
            message  => $msg,
        });
        return [];    # Don't return an app error for this.
    }

    # Load the necessary prototypes. Some prototypes may have the auto-crop
    # option disabled.
    my @prototypes = $app->model('thumbnail_prototype')->load({
        blog_id  => $asset->blog_id,
        autocrop => 1,
    });

    my @thumbs;
    foreach my $prototype ( @prototypes ) {
        my $prototype_key = ( $prototype->basename // '' ) ne ''
                              ? $prototype->basename
                              : 'custom_' . $prototype->id;

        # Does a crop with this prototype exist? If yes, give up. We don't want
        # to auto-crop and potentially destroy a manually cropped image.
        # Look for prototype mappings. Theme-built prototypes are saved as
        # dirified basenames, but previously they just used double colons to
        # join values which is messy and causes JS trouble. But, since maps may
        # exist to these old-style keys, look for any in addition to the new
        # style.
        my $old_style_key = $prototype_key;
        $old_style_key    =~ s/__/::/;
        my $map           = $app->model('thumbnail_prototype_map')->load({
            asset_id      => $asset->id,
            prototype_key => [ $prototype_key, $old_style_key ],
        });
        next if $map && $app->model('asset')->exist( $map->cropped_asset_id );

        # Is this a cropped child asset? We don't want to create crops of child
        # assets. That could get into a rabbit hole of a child creating a child
        # creating a child... and quickly become a mess.
        next if defined $asset->parent;

        # A crop from this prototype doesn't exist. Let's build one!
        my $crop_box = _calculate_auto_crop_box({
            prototype => $prototype,
            asset     => $asset,
        });

        # Finally, create the thumbnail.
        push( @thumbs, _create_thumbnail({
            asset         => $asset,
            prototype_key => $prototype_key,
            w             => $crop_box->{w},
            h             => $crop_box->{h},
            x             => $crop_box->{x},
            y             => $crop_box->{y},
        }));
    }

    return \@thumbs;
}

sub _calculate_auto_crop_box {
    my ($arg_ref) = @_;
    my $prototype = $arg_ref->{prototype};
    my $asset     = $arg_ref->{asset};

    # Some basic variables get reset based upon the crop needs.
    my $w = 0; # The image width to crop to
    my $h = 0; # The image height to crop to
    my $x = 0;
    my $y = 0;

    my $max_w = $prototype->max_width;
    my $max_h = $prototype->max_height;

    my $asset_w = $asset->image_width;
    my $asset_h = $asset->image_height;

    # The prototype height is defined, and the width can be variable.
    # Or, the prototype width is defined, and the height can be variable.
    if ( $max_w == 0 || $max_h == 0 ) {
        $w = $asset_w;
        $h = $asset_h;
    }
    # Is the image bigger than the desired prototype size? If yes, we need
    # to crop to meet the desired proportions.
    elsif ( $asset_w >= $max_w && $asset_h >= $max_h ) {
        # Create a crop box by defining how the image can be fit into the
        # prototype box. Calculate a desired width and height to be used in
        # defining the crop box and testing how the image can be resized.
        my $desired_w = ($asset_h * $max_w) / $max_h;
        my $desired_h = ($asset_w * $max_h) / $max_w;

        # The image is taller than needed for the prototype, and the image is
        # tall enough to be cropped to the desired proportions.
        if ( $desired_h > $max_h && $desired_h <= $asset_h ) {
            $w = $asset_w;
            $h = $desired_h;
            $x = 0;
            $y = ($asset_h - $desired_h) / 2; # Center the crop
        }
        # Image is not tall enough; can we crop to width?
        elsif ( $desired_w <= $asset_w ) {
            my $desired_w = ($asset_h * $max_w) / $max_h;
            $w = $desired_w;
            $h = $asset_h;
            $x = ($asset_w - $desired_w) / 2; # Center the crop
            $y = 0;
        }
        # The image isn't big enough to meet the desired size proportions. Can
        # this even happen? The above checks should catch an asset that isn't
        # tall enough to crop or wide enough to crop, and if an image isn't
        # tall enough *and* wide enough it shouldn't be in the parent `if`
        # statement (checking asset w/h against prototype w/h), and would go to
        # the else below... right?
        else {
            $w = $asset_w;
            $h = $asset_h;
        }
    }
    # The image is *not* bigger that the desired prototype size. The image
    # can't be cropped correctly; just resize to the max width or height,
    # if necessary.
    else {
        $w = $asset_w;
        $h = $asset_h;
    }

    # Return the values that define the crop box. With these, the top-left
    # corner of the box is defined and the width and height of the crop box is
    # defined.
    return {
        w => $w,
        h => $h,
        x => $x,
        y => $y,
    };
}

# Create the thumbnail based on the crop box (from the $w, $h, $x, and $y
# variables) and resize (based on the prototype dimensions).
sub _create_thumbnail {
    my ($arg_ref) = @_;
    my $asset     = $arg_ref->{asset};
    my $app       = MT->instance;
    my $plugin    = MT->component('imagecropper');

    my $blog = $app->model('blog')->load({ id => $asset->blog_id });

    my $quality = $plugin->get_config_value(
        'default_quality',
        'blog:' . $blog->id
    );
    my $text_size = $plugin->get_config_value(
        'annotate_fontsize',
        'blog:' . $blog->id
    );

    my $key      = $arg_ref->{prototype_key};
    my $w        = $arg_ref->{w};
    my $h        = $arg_ref->{h};
    my $x        = $arg_ref->{x};
    my $y        = $arg_ref->{y};
    my $type     = $arg_ref->{type} || 'jpg';
    $quality     = $arg_ref->{quality} || $quality;
    my $annotate = $arg_ref->{annotate};
    my $text     = $arg_ref->{text};
    $text_size   = $arg_ref->{text_size} || $text_size;
    my $text_loc = $arg_ref->{text_location};
    my $text_rot = $arg_ref->{text_rotation};

    # Remove any previously-created asset based on this prototype before trying
    # to create a new one.
    _remove_old_asset({
        asset_id => $asset->id,
        key      => $key,
        blog_id  => $blog->id,
    });

    my $prototype;
    if ( $key =~ /custom_(\d+)/ ) {
        $prototype = MT->model('thumbnail_prototype')->load({ id => $1 });
    }
    else {
        $prototype = MT->model('thumbnail_prototype')->load({
            blog_id  => $blog->id,
            basename => $key,
        });
    }
    die "Prototype $key not found!" unless $prototype;

    my @cropped_file_parts = crop_filename(
        $asset,
        Prototype => $key,
        Type      => $type,
    );

    my ( $cache_path, $cache_url );
    my $archivepath = $blog->archive_path;
    my $archiveurl  = $blog->archive_url;
    $cache_path = $cache_url = $asset->_make_cache_path( undef, 1 );
    $cache_path =~ s!%a!$archivepath!;

    $cache_url =~ s!%a!$archiveurl!;
    my $cropped_path =
      File::Spec->catfile( $cache_path, @cropped_file_parts );

    my $cropped_url_filename = encode_url( $cropped_file_parts[-1] );
    my $cropped_url = caturl( $cache_url, $cropped_url_filename );

    my ( $base, $path, $ext ) =
      File::Basename::fileparse( File::Spec->catfile(@cropped_file_parts),
        qr/[A-Za-z0-9]+$/ );

    require MT::Image;
    my $img = MT::Image->new( Filename => $asset->file_path )
        or $app->log({
            blog_id  => $blog->id,
            category => 'load',
            class    => 'Image Cropper',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper is unable to load the file '
                . $asset->file_path . ' for asset ID ' . $asset->id . ', '
                . MT::Image->errstr
        });

    # Crop the image to the desired proportions.
    my $data = crop_image(
        $img,
        Width   => $w,
        Height  => $h,
        X       => $x,
        Y       => $y,
        Type    => $type,
        quality => $quality,
    );

    # Resize the cropped image to the desired prototype size. Check for a max
    # width of `0` to differentiate prototypes that should be variable width
    # (or, for a max height of `0`, variable height) and scale appropriately.
    # We don't actually *need* to supply both Width and Height values.
    if ($prototype->max_width == 0) {
        $data = $img->scale(
            # Width  => $prototype->max_width,
            Height => $prototype->max_height,
        );
    }
    else {
        $data = $img->scale(
            Width  => $prototype->max_width,
            # Height => $prototype->max_height,
        );
    }

    if ( $annotate && $text ) {
        my $plugin = MT->component("ImageCropper");
        my $scope  = "blog:" . $blog->id;
        my $fam    = $plugin->get_config_value( 'annotate_fontfam', $scope );
        $data = annotate(
            $img,
            text     => $text,
            family   => $fam,
            size     => $text_size,
            location => $text_loc,
            rotation => $text_rot,
        );
    }
    require MT::FileMgr;
    my $fmgr = $blog ? $blog->file_mgr : MT::FileMgr->new('Local');
    unless ($fmgr) {
        $app->log({
            blog_id  => $blog->id,
            category => 'filemanager',
            class    => 'Image Cropper',
            level    => $app->model('log')->ERROR(),
            message  => 'Image Cropper is unable to initialize File Manager.',
        });
        return undef;
    }
    if ( $cache_path =~ /^%r/ ) {
        my $site_path = $blog->site_path;
        $cache_path =~ s/%r/$site_path/;
    }
    unless ( $fmgr->can_write($cache_path) ) {
        $app->log({
            blog_id  => $blog->id,
            category => 'filemanager',
            class    => 'Image Cropper',
            level    => $app->model('log')->ERROR(),
            message  => "Image Cropper is unable to write to $cache_path.",
        });
        return undef;
    }
    my $error = '';
    if ( !-d $cache_path ) {
        require MT::FileMgr;
        unless ( $fmgr->mkpath($cache_path) ) {
            $app->log({
                blog_id  => $blog->id,
                category => 'filemanager',
                class    => 'Image Cropper',
                level    => $app->model('log')->ERROR(),
                message  => 'Image Cropper is unable to make the cache path '
                    . "$cache_path.",
            });
            return undef;
        }
    }

    my $bytes = $fmgr->put_data(
        $data,
        File::Spec->catfile( $cache_path, @cropped_file_parts ),
        'upload'
    )
        or $error =
            MT->translate( "Error creating cropped file: [_1]", $fmgr->errstr );

    my $asset_cropped = new MT::Asset::Image;
    $asset_cropped->blog_id( $blog->id );
    $asset_cropped->url($cropped_url);
    $asset_cropped->file_path($cropped_path);
    $asset_cropped->file_name("$base$ext");
    $asset_cropped->file_ext($ext);
    $asset_cropped->image_width( $prototype->max_width );
    $asset_cropped->image_height( $prototype->max_height );
    my $created_by = $app->can('user') ? $app->user->id : 0;
    $asset_cropped->created_by( $created_by );
    $asset_cropped->label(
        $app->translate(
            "[_1] ([_2])",
            $asset->label || $asset->file_name,
            $prototype->label
        )
    );
    $asset_cropped->parent( $asset->id );
    $asset_cropped->mime_type( $asset->mime_type );
    $asset_cropped->save or die $asset_cropped->errstr;

    my $msg = sprintf( 'Image Cropper created a new child asset (ID %d) based '
                     . 'on the Thumbnail Prototype &ldquo;%s&rdquo; and the '
                     . 'parent asset %s(ID %d).',
        $asset_cropped->id,
        $prototype->label,
        ( $asset->label ? '&ldquo;'.$asset->label.'&rdquo; ' : '' ),
        $asset->id
    );
    $app->log({
        blog_id   => $blog->id,
        category  => 'new',
        class     => 'asset',
        level     => $app->model('log')->INFO(),
        message   => $msg,
    });

    my $map = MT->model('thumbnail_prototype_map')->new;
    $map->asset_id( $asset->id );
    $map->prototype_key($key);
    $map->cropped_asset_id( $asset_cropped->id );
    $map->cropped_x($x);
    $map->cropped_y($y);
    $map->cropped_w($w);
    $map->cropped_h($h);
    $map->save or die $map->errstr;

    return {
        error         => $error,
        proto_key     => $key,
        cropped       => caturl(@cropped_file_parts),
        cropped_path  => $cropped_path,
        cropped_url   => $cropped_url,
        cropped_size  => file_size($asset_cropped),
        cropped_asset => $asset_cropped,
    };
}

# When creating a new thumbnail we want to remove any old asset based on the
# same prototype before trying to create a new one.
sub _remove_old_asset {
    my ($arg_ref) = @_;
    my $asset_id  = $arg_ref->{asset_id};
    my $key       = $arg_ref->{key};
    my $blog_id   = $arg_ref->{blog_id};

    # Look for prototype mappings. Theme-built prototypes are saved as
    # dirified basenames, but previously they just used double colons to
    # join values which is messy and causes JS trouble. But, since maps may
    # exist to these old-style keys, look for any in addition to the new
    # style.
    my $old_style_key = $key;
    $old_style_key =~ s/__/::/;

    my $oldmap = MT->model('thumbnail_prototype_map')->load({
        asset_id      => $asset_id,
        prototype_key => [$key, $old_style_key],
    });

    if ($oldmap) {
        $oldmap->remove()
            or MT->log({
                blog_id  => $blog_id,
                category => 'delete',
                class    => 'Image Cropper',
                level    => MT->model('log')->ERROR(),
                message  => 'Image Cropper is unable to remove the prototype '
                    . 'asset map with ID ' . $oldmap->cropped_asset_id . ', '
                    . $oldmap->errstr,
            });

        my $oldasset
            = MT->model('asset')->load({ id => $oldmap->cropped_asset_id });
        if ($oldasset) {
            $oldasset->remove()
                or MT->log({
                    blog_id  => $blog_id,
                    category => 'delete',
                    class    => 'Image Cropper',
                    level    => MT->model('log')->ERROR(),
                    message  => 'Image Cropper is unable to remove the asset '
                        . 'ID ' . $oldmap->cropped_asset_id . ', '
                        . $oldasset->errstr,
                });
        }
    }
}

# Automatically create thumbnails on image upload. (Well, sort of: create
# worker jobs to create thumbnails. When the worker runs it will create the
# thumbnail, if necessary.)
sub upload_file_callback {
    my $cb = shift;
    my (%params) = @_;
    insert_auto_crop_job( $params{'Asset'} );
}

sub insert_auto_crop_job {
    shift if $_[0] eq __PACKAGE__; # supports method invocation
    my ($asset) = @_;

    # This must be an image for us to build thumbails, and the file needs to
    # exist, of course!
    return 1 unless $asset->class =~ m/(image|photo)/;

    if ( !-f $asset->file_path ) {
        MT->instance->log({
            blog_id  => $asset->blog_id,
            category => 'load',
            class    => 'Image Cropper',
            level    => MT->instance->model('log')->ERROR(),
            message  => 'Image Cropper is unable to load the file '
                . $asset->file_path . ' for asset ID ' . $asset->id . '; a '
                . 'worker job to generate Auto-Crop images will not be created.'
        });
        return 1;
    }

    # Are there any Prototypes with auto crop enabled?
    my $prototypes = MT->model('thumbnail_prototype')->exist({
        blog_id  => $asset->blog_id,
        autocrop => 1,
    });

    if ( $prototypes ) {
        # There are Prototypes with auto crop enabled, so insert a worker. The
        # worker will figure out which prototype sizes need building and create
        # them.
        require TheSchwartz::Job;
        require MT::TheSchwartz;
        my $job = TheSchwartz::Job->new();
        $job->funcname(  'ImageCropper::Worker::AutoCrop' );
        $job->coalesce(  $asset->id                       );
        $job->uniqkey(   $asset->id                       );
        $job->priority(  2                                );
        $job->run_after( time()                           );
        MT::TheSchwartz->insert( $job );
    }

    return 1;
}

# Update the asset picker to hide any child assets, cleaning up the picker
# screen.
sub app_pre_listing_dialog_list_asset {
    my ($cb, $app, $terms, $args, $param, $hasher) = @_;

    # Give up if the "hide" option wasn't selected; user wants to see all
    # assets.
    my $plugin = $app->component('ImageCropper');
    return unless $plugin->get_config_value(
        'hide_child_assets',
        'blog:' . $app->blog->id
    );

    $terms->{parent} = \'IS NULL';
}

1;

__END__
