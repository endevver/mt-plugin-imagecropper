# This code is licensed under the GPLv2
# Copyright (C) 2009 Endevver LLC.

package ImageCropper::Prototype;

use strict;
use warnings;

use base qw( MT::Object );

__PACKAGE__->install_properties( {
        column_defs => {
            'id'           => 'integer not null auto_increment',
            'basename'     => 'string(255)',
            'blog_id'      => 'integer not null',
            'label'        => 'string(100) not null',
            'max_width'    => 'smallint',
            'max_height'   => 'smallint',
            'compression'  => 'string(30)',
            'autocrop'     => 'boolean',
        },
        audit   => 1,
        indexes => {
            blog_id => 1,
            labels  => { columns => [ 'blog_id', 'label' ], },
        },
        datasource  => 'crop',
        primary_key => 'id',
    }
);

sub class_label {
    MT->translate("Thumbnail Prototype");
}

sub class_label_plural {
    MT->translate("Thumbnail Prototypes");
}

# The MT5 listing screen
sub listing_screen {
    return {
        primary => 'created_on',
        default_sort_key => 'created_on',
        screen_label => 'Thumbnail Prototypes Test!',
    };
}

sub list_properties {
    return {
        id => {
            auto    => 1,
            label   => 'ID',
            order   => 100,
            display => 'optional',
        },
        label => {
            base    => '__virtual.string',
            col     => 'label',
            label   => 'Label',
            order   => 200,
            display => 'default',
            html => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $uri = $app->uri . '?__mode=edit_prototype&id=' . $obj->id
                    . '&blog_id=' . $obj->blog_id;
                return '<a href="javascript:void(0)"'
                    . 'onclick="jQuery.fn.mtDialog.open(\''
                    . $uri . '\')">' . $obj->label . '</a>';
            },
        },
        max_width => {
            auto    => 1,
            label   => 'Max Width',
            order   => 300,
            display => 'default',
        },
        max_height => {
            auto    => 1,
            label   => 'Max Height',
            order   => 400,
            display => 'default',
        },
        autocrop => {
            auto    => 1,
            label   => 'Auto-Crop Enabled?',
            order   => 500,
            display => 'default',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                return $obj->autocrop ? 'Yes' : 'No';
            }
        },
        created_by => {
            base  => '__virtual.author_name',
            order => 500,
            display => 'default',
        },
        created_on => {
            base    => '__virtual.created_on',
            order   => 600,
            display => 'default',
        },
    };
}

sub edit_prototype {
    my $app     = shift;
    my ($param) = @_;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $blog    = $app->blog;

    $param ||= {};

    my $obj;
    if ( $q->param('id') ) {
        $obj = MT->model('thumbnail_prototype')->load( $q->param('id') );
    }
    else {
        $obj = MT->model('thumbnail_prototype')->new();
    }

    $param->{blog_id}    = $blog->id;
    $param->{id}         = $obj->id;
    $param->{basename}   = $obj->basename;
    $param->{label}      = $obj->label;
    $param->{max_width}  = $obj->max_width;
    $param->{max_height} = $obj->max_height;
    $param->{autocrop}   = $obj->autocrop;
    $param->{screen_id}  = 'edit-prototype';
    return $app->load_tmpl( 'dialog/edit.tmpl', $param );
}

sub save_prototype {
    my $app = shift;
    my $param;
    my $q = $app->can('query') ? $app->query : $app->param;
    my $obj = MT->model('thumbnail_prototype')->load( $q->param('id') )
        || MT->model('thumbnail_prototype')->new;

    $obj->$_( $q->param($_) )
        foreach (qw(blog_id max_width max_height label basename));

    # Check or uncheck the Enable Autocrop checkbox.
    my $autocrop = $q->param('autocrop') ? 1 : 0;
    $obj->autocrop( $autocrop );

    $obj->save or return $app->error( $obj->errstr );

    return $app->redirect(
        $app->mt_uri . "?__mode=list&_type=thumbnail_prototype&blog_id="
            . $q->param('blog_id') . "&prototype_saved=1" );
}

sub del_prototype {
    my ($app) = @_;
    $app->validate_magic or return;
    my $q = $app->can('query') ? $app->query : $app->param;
    my @protos = $q->param('id');
    for my $pid (@protos) {
        my $p = MT->model('thumbnail_prototype')->load($pid) or next;
        $p->remove;

        $app->log({
            author_id => $app->user->id,
            blog_id   => $app->blog->id,
            category  => 'delete',
            class     => 'Image Cropper',
            level     => $app->model('log')->INFO(),
            message   => 'The thumbnail prototype &ldquo;' . $p->label .
                '&rdquo; has been deleted.'
        });
    }
    $app->add_return_arg( prototype_removed => 1 );
    $app->call_return;
}

1;

__END__
